#!/usr/bin/env python3
"""Record every fixed English line that has no bundled clip, so English no longer waits
for (or fails without) the cloud voice. German and Polish already have these as clips.

  Marek         -> assets/audio/tts_en/<key>.wav      voice bm_george
  the AED       -> assets/audio/tts_en/<key>.wav      voice af_bella + the robot effect
  Anna          -> assets/audio/tts_en/<key>.wav      voice af_sky
  the instructor's hints, refusals and AED lines
                -> assets/audio/coaching/en/<name>.wav  voice am_adam (matched by text)

Voices are the ones the app uses for live English speech (NaretUniAPIClient
.CLOUD_ENGLISH_VOICES), so recorded and live lines sound the same. Every clip is
transcribed back and compared with its text; nothing is written unless all match.
Lines whose clip already exists with the same text are skipped.

The app configuration JSON comes on stdin, so the access key is never stored or printed:
  adb exec-out run-as de.uni_greifswald.naret.cprwitness cat files/config.json | python tools/bake_english_fixed_lines.py
With --list it only prints what would be recorded and needs neither the key nor the network.
"""
import difflib, hashlib, io, json, re, struct, sys, urllib.request, uuid, wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
AUDIO = ROOT / 'assets/audio'
sys.stdout.reconfigure(encoding='utf-8')
api = json.load(sys.stdin)['api'] if '--list' not in sys.argv else {'api_key': ''}
KEY = api['api_key']
BASE = str(api.get('base_url', 'https://apphubai.wolke.uni-greifswald.de/v1')).rstrip('/')
CRLF = '\r\n'
VOICES = {'instructor': 'am_adam', 'anna': 'af_sky', 'marek': 'bm_george', 'aed': 'af_bella'}
# The instructor's lines that are spoken as they stand (not the long on-screen AED texts).
INSTRUCTOR_GUIDANCE = ['aed_arrived', 'aed_pads_how', 'aed_resume', 'aed_resume_only', 'aed_wait']
INSTRUCTOR_UI = ['coach.scene_unsafe', 'coach.scene_unsafe_again', 'coach.shake_firmly', 'coach.open_airway_hint',
    'coach.hands_on_box', 'coach.bvm_place_mask', 'coach.bvm_squeeze',
    'error.shoulders_not_seen', 'error.breathing_not_seen', 'error.breaths_not_seen']


def post(path, body, headers):
    request = urllib.request.Request(BASE + path, data=body, headers={'Authorization': 'Bearer ' + KEY, **headers})
    last = None
    for _ in range(3):
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                return response.read()
        except OSError as error:
            last = error
    raise RuntimeError(str(last)[:120])


def pcm_of(wav_bytes):
    """(samples int16, rate) of a mono 16-bit WAV, also one streamed with a placeholder length."""
    at = wav_bytes.index(b'fmt ')
    fmt_len = struct.unpack('<I', wav_bytes[at + 4:at + 8])[0]
    _tag, channels, rate, _bytes, align, bits = struct.unpack('<HHIIHH', wav_bytes[at + 8:at + 24])
    assert channels == 1 and bits == 16, (channels, bits)
    pcm = wav_bytes[wav_bytes.index(b'data', at + 8 + fmt_len) + 8:]
    return np.frombuffer(pcm[:len(pcm) - len(pcm) % align], dtype=np.int16), rate


def wav_of(samples, rate):
    out = io.BytesIO()
    with wave.open(out, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(samples.astype(np.int16).tobytes())
    return out.getvalue()


def robot(samples, rate):
    # The same effect as NaretAudioManager.robot_voice and build/tmp/robot_aed_clips.py.
    x = samples.astype(np.float64)
    delay = int(0.007 * rate)
    y = 0.6 * x + 0.45 * np.concatenate([np.zeros(delay), x[:-delay]])
    y *= 0.7 + 0.3 * np.sin(2.0 * np.pi * 95.0 * np.arange(len(x)) / rate)
    peak = np.abs(y).max()
    if peak > 0: y *= np.abs(x).max() / peak
    return np.clip(y, -32768, 32767).astype(np.int16)


def speak(text, speaker):
    # 'tts-1' is the name the app asks for; 'kokoro:82m' is how the service lists the same voices.
    last = None
    for model in ('tts-1', 'kokoro:82m'):
        body = json.dumps({'model': model, 'input': text, 'response_format': 'wav', 'voice': VOICES[speaker]}).encode()
        try:
            data = post('/audio/speech', body, {'Content-Type': 'application/json'})
            if data[:4] == b'RIFF':
                return pcm_of(data)
            last = RuntimeError('no WAV returned by ' + model)
        except RuntimeError as error:
            last = error
    raise last


def heard(wav_bytes):
    boundary = uuid.uuid4().hex
    body = b''
    for name, value in (('model', 'large-v3'), ('language', 'en'), ('response_format', 'json')):
        body += ('--' + boundary + CRLF + 'Content-Disposition: form-data; name="' + name + '"' + CRLF + CRLF + value + CRLF).encode()
    body += ('--' + boundary + CRLF + 'Content-Disposition: form-data; name="file"; filename="s.wav"' + CRLF
        + 'Content-Type: audio/wav' + CRLF + CRLF).encode() + wav_bytes + (CRLF + '--' + boundary + '--' + CRLF).encode()
    return str(json.loads(post('/audio/transcriptions', body, {'Content-Type': 'multipart/form-data; boundary=' + boundary})).get('text', ''))


def words(text):
    return re.sub(r'[^\w ]', ' ', text.lower()).split()


def load(path):
    raw = path.read_text(encoding='utf-8-sig')
    return json.loads(raw)


# ---- what to record
lines = load(ROOT / 'data/bystander_lines.json')
guidance = load(ROOT / 'data/aed_helper_guidance.json')['languages']['en']
ui = load(ROOT / 'data/ui_texts.json')['strings']['en']
manifest_path = AUDIO / 'manifest.json'
manifest = load(manifest_path)
coach_path = AUDIO / 'coaching/manifest.json'
coach = load(coach_path)

keyed = []      # (key, speaker, text)
for key, line in lines.items():
    if key.startswith('_') or not isinstance(line, dict) or 'en' not in line:
        continue
    known = [c for c in manifest['clips'] if c['language'] == 'en' and c['key'] == key]
    if known and known[0]['text'] == line['en'] and (AUDIO / known[0]['file']).exists():
        continue
    keyed.append((key, 'anna' if line['speaker'] == 'anna' else line['speaker'], line['en']))
by_text = []    # (name, text)
have = {c['text'] for c in coach['clips'] if c['language'] == 'en'}
for key in INSTRUCTOR_GUIDANCE:
    if key in guidance and guidance[key] not in have:
        by_text.append((key, guidance[key]))
for key in INSTRUCTOR_UI:
    if key in ui and ui[key] not in have:
        by_text.append((key.replace('.', '_'), ui[key]))
print('to record: %d character lines, %d instructor lines' % (len(keyed), len(by_text)))
if '--list' in sys.argv:
    # What would be recorded, without contacting the speech service.
    for key, speaker, text in keyed: print('  %-8s %-18s %s' % (speaker, key, text))
    for name, text in by_text: print('  %-8s %-18s %s' % ('instr.', name, text))
    raise SystemExit(0)

# ---- record and check, in memory
ready_keyed, ready_text = [], []
for key, speaker, text in keyed:
    samples, rate = speak(text, speaker)
    said = heard(wav_of(samples, rate))
    match = difflib.SequenceMatcher(None, words(text), words(said)).ratio()
    print('%-8s %-18s %4.1f s  match %.2f  %s' % (speaker, key, len(samples) / rate, match, said.strip()))
    if match < 0.8:
        raise SystemExit('clip does not say its text: ' + key)
    if speaker == 'aed':
        samples = robot(samples, rate)
    ready_keyed.append((key, speaker, text, wav_of(samples, rate), len(samples) / rate))
for name, text in by_text:
    samples, rate = speak(text, 'instructor')
    said = heard(wav_of(samples, rate))
    match = difflib.SequenceMatcher(None, words(text), words(said)).ratio()
    print('%-8s %-18s %4.1f s  match %.2f  %s' % ('instr.', name, len(samples) / rate, match, said.strip()))
    if match < 0.8:
        raise SystemExit('clip does not say its text: ' + name)
    ready_text.append((name, text, wav_of(samples, rate)))

# ---- everything spoke correctly: write
(AUDIO / 'tts_en').mkdir(parents=True, exist_ok=True)
(AUDIO / 'coaching/en').mkdir(parents=True, exist_ok=True)
for key, speaker, text, data, seconds in ready_keyed:
    (AUDIO / 'tts_en' / (key + '.wav')).write_bytes(data)
    manifest['clips'] = [c for c in manifest['clips'] if not (c['language'] == 'en' and c['key'] == key)]
    manifest['clips'].append({'key': key, 'language': 'en', 'speaker': speaker, 'text': text,
        'file': 'tts_en/%s.wav' % key, 'duration_s': round(seconds, 3), 'sha256': hashlib.sha256(data).hexdigest(),
        'generator': 'cloud tts-1 %s%s' % (VOICES[speaker], ' + robot effect' if speaker == 'aed' else '')})
for name, text, data in ready_text:
    path = 'res://assets/audio/coaching/en/%s.wav' % name
    (AUDIO / 'coaching/en' / (name + '.wav')).write_bytes(data)
    coach['clips'] = [c for c in coach['clips'] if c['path'] != path]
    coach['clips'].append({'text': text, 'language': 'en', 'path': path})
manifest_path.write_bytes(('﻿' + json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))
coach_path.write_text(json.dumps(coach, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
print('written: %d character clips, %d instructor clips' % (len(ready_keyed), len(ready_text)))
