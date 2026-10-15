"""Verify the local large-v3 server using existing synthetic test recordings."""
import json
from pathlib import Path
from compare_speech_models import transcribe, ROOT

rows = []
for name in ('asr-normal.wav', 'asr-fast.wav'):
    transcript, seconds = transcribe(ROOT / 'build' / name, 8767)
    rows.append({'recording': name, 'model': 'large-v3',
                 'transcript': transcript, 'seconds': seconds})
    print(name, repr(transcript), seconds, 'seconds')
(ROOT / 'build' / 'large-v3-validation.json').write_text(
    json.dumps(rows, indent=2), encoding='utf-8')
