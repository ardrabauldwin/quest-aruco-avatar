"""Prepare fixed instructor guidance so stage announcements need no network TTS."""
import json
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
guide = json.loads((root / 'data/coach_steps.json').read_text(encoding='utf-8'))
output = root / 'assets/audio/coaching'
clips = []
for language, steps in guide.items():
    (output / language).mkdir(parents=True, exist_ok=True)
    for name, text in steps.items():
        request = urllib.request.Request('http://127.0.0.1:8768/audio/speech', data=json.dumps({'input': text, 'language': language, 'speaker': 'instructor'}).encode(), headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=45) as response:
            wav = response.read()
        if wav[:4] != b'RIFF': raise RuntimeError('Invalid voice output')
        (output / language / (name + '.wav')).write_bytes(wav)
        clips.append({'text': text, 'language': language, 'path': 'res://assets/audio/coaching/' + language + '/' + name + '.wav'})
(output / 'manifest.json').write_text(json.dumps({'clips': clips}, ensure_ascii=False, indent=2), encoding='utf-8')
print('Prepared', len(clips), 'fixed instructor lines with the separate instructor voices.')
