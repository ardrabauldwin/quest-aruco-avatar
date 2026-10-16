"""WSL deployment after the served-model regression gate; reversible routing."""
import json
import os
import signal
import sys
import subprocess
import time
import urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parent
script=str(ROOT/'serve_interpreter.py')
assert Path('/opt/naret-training/v3-adapter/adapter_model.safetensors').exists()
# Replace only the temporary process started with this exact executable/script.
for path in Path('/proc').iterdir():
    if not path.name.isdigit(): continue
    try:
        cmd=(path/'cmdline').read_bytes().split(b'\0')
        if len(cmd)>=2 and cmd[0]==b'/opt/naret-training/bin/python' and cmd[1].decode()==script:
            os.kill(int(path.name),signal.SIGTERM)
    except (OSError,UnicodeError): pass
unit=Path('/etc/systemd/system/naret-interpreter.service')
unit.write_text('[Unit]\nDescription=NaReT v3 observation interpreter\nAfter=network.target\n[Service]\nType=simple\nExecStart=/opt/naret-training/bin/python '+script+'\nRestart=on-failure\nRestartSec=3\n[Install]\nWantedBy=multi-user.target\n')
subprocess.run(['systemctl','daemon-reload'],check=True,timeout=15)
subprocess.run(['systemctl','enable','--now','naret-interpreter'],check=True,timeout=20)
ready=False
for attempt in range(30):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8771/health',timeout=2) as response:
            ready=response.status==200
        if ready: break
    except OSError: pass
    time.sleep(1)
assert ready, 'Interpreter failed readiness; live route unchanged'
if '--prepare-only' in sys.argv:
    print('Interpreter service ready; live route unchanged pending regression check.')
    raise SystemExit(0)
check=json.loads((ROOT/'v3/serving_check.json').read_text())
assert check['correct']>=30 and check['false_progression']==0
dropin=Path('/etc/systemd/system/naret-dialogue.service.d/observation-interpreter.conf')
dropin.parent.mkdir(exist_ok=True)
previous=dropin.read_bytes() if dropin.exists() else None
try:
    dropin.write_text('[Service]\nEnvironment=NARET_INTERPRETER_URL=http://127.0.0.1:8771\n')
    subprocess.run(['systemctl','daemon-reload'],check=True,timeout=15)
    subprocess.run(['systemctl','restart','naret-dialogue'],check=True,timeout=20)
except Exception:
    if previous is None: dropin.unlink(missing_ok=True)
    else: dropin.write_bytes(previous)
    subprocess.run(['systemctl','daemon-reload'],timeout=15)
    subprocess.run(['systemctl','restart','naret-dialogue'],timeout=20)
    raise
print('Deployed v3 observation adapter; Anna dialogue remains qwen3:4b-instruct. APK unchanged.')
