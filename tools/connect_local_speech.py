"""Configure USB-local speech/CCBM without altering credentials or calibration."""
import json
from pathlib import Path
import subprocess

ADB = Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'
PREFIX = [str(ADB), '-s', '2G0YC5ZH0G00HS']
PACKAGE = 'de.uni_greifswald.naret.cprwitness'

def run(args, payload=None):
    result = subprocess.run(PREFIX + args, input=payload, capture_output=True, timeout=30)
    if result.returncode:
        raise RuntimeError('Device command failed; no private data printed')
    return result.stdout

def write_verified(path, payload):
    run(['exec-in', 'run-as', PACKAGE, 'tee', path], payload)
    actual = run(['exec-out', 'run-as', PACKAGE, 'cat', path]).replace(b'\r\n', b'\n')
    if actual != payload:
        raise RuntimeError('Configuration verification failed')
    run(['shell', 'run-as', PACKAGE, 'chmod', '600', path])

def main():
    # Read privately, never print an existing credential.
    exists = subprocess.run(PREFIX + ['shell', 'run-as', PACKAGE, 'test', '-f', 'files/config.json'], capture_output=True, timeout=20)
    if exists.returncode not in (0, 1):
        raise RuntimeError('Cannot inspect device configuration')
    config = json.loads(run(['exec-out', 'run-as', PACKAGE, 'cat', 'files/config.json'])) if exists.returncode == 0 else {}
    config.setdefault('api', {})['local_asr_url'] = 'http://127.0.0.1:8767/inference'
    write_verified('files/config.json', (json.dumps(config) + '\n').encode())
    write_verified('files/ccbm.cfg', b'[ccbm]\nendpoint="http://127.0.0.1:8766/infer"\n')
    for port in (8766, 8767):
        run(['reverse', f'tcp:{port}', f'tcp:{port}'])
    print('Local speech and CCBM configuration verified; USB forwarding enabled.')

if __name__ == '__main__':
    main()
