"""Bounded, read-only USB transcript capture; no audio or configuration export.

Only NARET_TRANSCRIPT lines are saved. They can be truncated by the app at 160
characters, and require human labeling; do not treat scenario acceptance as gold.
"""
import argparse
import hashlib
import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--adb',required=True)
    parser.add_argument('--serial',required=True)
    parser.add_argument('--seconds',type=int,default=1800)
    args=parser.parse_args()
    root=Path(__file__).resolve().parent/'real_headset'
    root.mkdir(exist_ok=True)
    session=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    target=root/f'capture-{session}.jsonl'
    status=root/'capture_status.json'
    seen=set(); count=0; deadline=time.monotonic()+min(max(args.seconds,1),1800)
    def update(state,error=None):
        status.write_text(json.dumps(dict(status=state,session_id=session,rows=count,
            path=str(target),error=error,training_eligible=False),indent=2),encoding='utf-8')
    update('collecting')
    try:
        with target.open('x',encoding='utf-8') as out:
            while time.monotonic()<deadline:
                result=subprocess.run([args.adb,'-s',args.serial,'logcat','-d','-v','threadtime'],capture_output=True,timeout=15)
                if result.returncode:
                    # APK installs and USB reconnects temporarily interrupt ADB.
                    # Keep the same capture/session open until its deadline.
                    update('waiting_for_device','ADB read failed; retrying without changing settings')
                    time.sleep(3)
                    continue
                for line in result.stdout.decode('utf-8',errors='replace').splitlines():
                    if 'NARET_TRANSCRIPT ' not in line:
                        continue
                    key=hashlib.sha256(line.encode()).hexdigest()
                    if key in seen:
                        continue
                    seen.add(key)
                    text=line.split('NARET_TRANSCRIPT ',1)[1].strip()
                    if not text:
                        continue
                    row=dict(id=key,session_id=session,source='quest_android_logcat',
                        device_log_prefix=line.split('NARET_TRANSCRIPT ',1)[0],
                        utterance=text,possibly_truncated=len(text)>=160,
                        speaker_id=None,label=None,human_reviewed=False,
                        training_eligible=False,provenance='real_headset_recognised_text')
                    out.write(json.dumps(row,ensure_ascii=False)+'\n'); out.flush(); count+=1
                update('collecting')
                time.sleep(3)
        update('complete')
    except Exception as exc:
        update('failed',type(exc).__name__)
        raise

if __name__=='__main__': main()
