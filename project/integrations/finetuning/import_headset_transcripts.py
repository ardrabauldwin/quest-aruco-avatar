"""Import genuine saved ASR output, preserving provenance and uncertain labels.

Two model outputs from the same recording are one family, not two independent
speakers. Never silently turn synthetic speech or missing audio truth into data.
"""
import csv
import hashlib
import json
from pathlib import Path
from prepare import SYSTEM
ROOT=Path(__file__).resolve().parent
SOURCE=ROOT.parents[1]/'build'/'speech-model-comparison.csv'
def main():
    destination=ROOT/'real_headset'
    destination.mkdir(exist_ok=True)
    audio=SOURCE.parent/'last-headset-microphone.wav'
    rows=[]
    for item in csv.DictReader(SOURCE.open(encoding='utf-8',newline='')):
        if not item['case'].startswith('headset_'):
            continue
        text=' '.join(item['transcript'].split())
        rows.append(dict(id='saved-headset-'+item['model'],family='saved-headset-latest',
            provenance='recorded_headset_asr',source=str(SOURCE.relative_to(ROOT.parents[1])),
            asr_model=item['model'],utterance=text,raw_transcript=item['transcript'],
            speaker_id=None,session_id=None,language='en',
            label_candidate=dict(action='check_breathing',kind='report',result='abnormal',evidence=text),
            human_reviewed=False,spoken_ground_truth=None,
            label_basis='meaning of the saved ASR text; original intended speech is not verified',
            split='development_only',training_eligible=False))
    (destination/'candidates.jsonl').write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in rows),encoding='utf-8')
    # Reuse for a development-only interpreter check, never a held-out score.
    checks=[]
    for row in rows:
        label=row['label_candidate']
        checks.append(dict(id=row['id'],utterance=row['utterance'],label=label,
            messages=[dict(role='system',content=SYSTEM),dict(role='user',content=row['utterance']),
                dict(role='assistant',content=json.dumps(label,ensure_ascii=False))]))
    (destination/'test.jsonl').write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in checks),encoding='utf-8')
    manifest=dict(rows=len(rows),independent_recording_families=len({r['family'] for r in rows}),
        source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        audio_available=audio.exists(),audio_current_sha256=hashlib.sha256(audio.read_bytes()).hexdigest() if audio.exists() else None,
        audio_link_verified=False,
        warning='The diagnostic WAV is overwritten by capture; its current contents may not match the historical comparison.',
        status='imported_not_trained',reason='Only one recording family; insufficient independent recordings for a real-data training/test split')
    (destination/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    (destination/'README.md').write_text('# Recovered real headset transcripts\n\nImported two ASR outputs from one saved headset recording. Synthetic comparison rows are excluded. Candidate labels describe the recognised text, not verified physical actions or independently transcribed speech. Neither candidate is human reviewed.\n\nThese are development examples only. They are not an independent test set and have not been used for training. A speaker/session-separated evaluation requires more real recordings. The latest WAV may have been overwritten since the comparison; its historical identity is not established.\n',encoding='utf-8')
    print(json.dumps(dict(rows=len(rows),recording_families=manifest['independent_recording_families'],status=manifest['status'])))
if __name__=='__main__': main()
