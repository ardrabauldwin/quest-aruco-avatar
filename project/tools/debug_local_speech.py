"""Temporary USB-only diagnostic: overwrite one latest WAV; forward to Whisper."""
from email.parser import BytesParser
from email.policy import default
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import urllib.request

LAST = Path(__file__).resolve().parents[1] / 'build/last-headset-microphone.wav'

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get('Content-Length', '0'))
        if self.path != '/inference' or not 0 < size <= 4 * 1024 * 1024:
            self.send_error(400)
            return
        body = self.rfile.read(size)
        content_type = self.headers.get('Content-Type', '')
        message = BytesParser(policy=default).parsebytes(('Content-Type: ' + content_type + '\r\nMIME-Version: 1.0\r\n\r\n').encode() + body)
        for part in message.iter_parts():
            if part.get_param('name', header='content-disposition') == 'file':
                audio = part.get_payload(decode=True)
                if audio and audio[:4] == b'RIFF':
                    LAST.write_bytes(audio)
        try:
            request = urllib.request.Request('http://127.0.0.1:8770/inference', data=body, headers={'Content-Type': content_type})
            with urllib.request.urlopen(request, timeout=25) as response:
                result = response.read()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(result)))
            self.end_headers()
            self.wfile.write(result)
        except Exception:
            self.send_error(502, 'Local recogniser unavailable')

    def log_message(self, *_):
        pass  # Never log the recording or recognised text.

if __name__ == '__main__':
    HTTPServer(('127.0.0.1', 8767), Handler).serve_forever()
