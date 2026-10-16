"""Local HTTP wrapper around the REAL compiled CCBM particle filter.

No replacement inference engine is implemented here. Requires build.sh outputs.
Bind localhost; use an authenticated HTTPS reverse proxy for a Quest connection.
"""
import argparse
import json
import math
from pathlib import Path
import shlex
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

ACTIONS = {'begin_check', 'check_responsiveness', 'call_emergency',
           'check_breathing', 'compression', 'compression_only', 'ventilation', 'handover'}


def parse_posterior(output, expected_steps):
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    header_index = next((i for i, line in enumerate(lines) if line.startswith('Time')), None)
    if header_index is None:
        raise ValueError('Missing CCBM action-estimation header')
    names = shlex.split(lines[header_index])[1:]
    rows = []
    for line in lines[header_index + 1:]:
        cells = line.split()
        if len(cells) == len(names) + 1:
            try:
                rows.append([float(cell) for cell in cells])
            except ValueError:
                continue
    if not rows or rows[-1][0] != expected_steps:
        raise ValueError('CCBM did not consume all observations')
    masses = {}
    for name, value in zip(names, rows[-1][1:]):
        if not math.isfinite(value) or value < 0:
            raise ValueError('Invalid posterior')
        tokens = name.strip('()').split()
        action = tokens[0] if tokens else 'UNKNOWN'
        if action in {'ventilation_first', 'ventilation_second'}:
            action = 'ventilation'
        masses[action] = masses.get(action, 0.0) + value
    total = sum(masses.values())
    if total <= 0 or abs(total - 1) > 0.01:
        raise ValueError('Unnormalised posterior')
    # Include FINISHED/BLOCKED when selecting; never silently renormalise them away.
    action = max(masses, key=masses.get)
    return {'engine': 'ccbm', 'action': action, 'probability': masses[action] / total}


def infer(observations, executable, states):
    if not isinstance(observations, list) or not 1 <= len(observations) <= 256:
        raise ValueError('Expected 1..256 observation codes')
    if any(not isinstance(item, str) or item not in ACTIONS for item in observations):
        raise ValueError('Unknown observation code')
    result = subprocess.run([str(executable), '-l', str(states)],
                            input='\n'.join(observations) + '\n', text=True,
                            capture_output=True, timeout=8, check=True)
    return parse_posterior(result.stdout, len(observations))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8766)
    parser.add_argument('--build', type=Path, default=Path(__file__).parent / 'out')
    args = parser.parse_args()
    executable, states = (args.build / 'p-filter').resolve(), (args.build / 'p.states').resolve()
    if not executable.is_file() or not states.is_file():
        parser.error('CCBM binaries are missing. Run build.sh on Linux first.')

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != '/infer':
                self.send_error(404)
                return
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 16384:
                    raise ValueError('Invalid request size')
                payload = json.loads(self.rfile.read(size))
                if not isinstance(payload, dict):
                    raise ValueError('Expected object')
                reply = infer(payload.get('observations'), executable, states)
                status = 200
            except (ValueError, TypeError):
                reply, status = {'error': 'invalid_request_or_posterior'}, 400
            except (OSError, subprocess.SubprocessError):
                reply, status = {'error': 'ccbm_unavailable'}, 503
            body = json.dumps(reply).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    HTTPServer(('127.0.0.1', args.port), Handler).serve_forever()


if __name__ == '__main__':
    main()
