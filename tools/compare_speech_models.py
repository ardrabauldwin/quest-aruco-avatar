"""Compare real local servers; synthetic speed trials aren't learner validation."""
import csv
import json
from pathlib import Path
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def transcribe(path, port):
    boundary = 'NaretModelComparison'
    fields = {'language': 'en', 'response_format': 'json'}
    body = b''.join(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode() for key, value in fields.items())
    body += f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="speech.wav"\r\nContent-Type: audio/wav\r\n\r\n'.encode()
    body += path.read_bytes() + f'\r\n--{boundary}--\r\n'.encode()
    start = time.monotonic()
    request = urllib.request.Request(f'http://127.0.0.1:{port}/inference', data=body, headers={'Content-Type': f'multipart/form-data; boundary={boundary}'})
    with urllib.request.urlopen(request, timeout=45) as response:
        text = str(json.load(response).get('text', '')).strip()
    return text, round(time.monotonic() - start, 3)

def main():
    cases = [('headset_latest', ROOT / 'build/last-headset-microphone.wav', ''),
             ('synthetic_normal', ROOT / 'build/asr-normal.wav', 'The scene is safe.'),
             ('synthetic_fast', ROOT / 'build/asr-fast.wav', 'The scene is safe.')]
    rows = []
    for case, path, reference in cases:
        for name, port in [('medium', 8770), ('large-v3-turbo', 8771)]:
            text, elapsed = transcribe(path, port)
            rows.append(dict(case=case, model=name, reference=reference, transcript=text, seconds=elapsed))
            print(case, name, repr(text), elapsed, 's')
    with (ROOT / 'build/speech-model-comparison.csv').open('w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

if __name__ == '__main__':
    main()
