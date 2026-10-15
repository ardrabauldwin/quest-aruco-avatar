"""Keep the USB-local training services reachable during a headset session.

WSL systemd services alone do not keep the distribution alive. A foreground
journal subscription does; its output is discarded. Restore missing USB reverse
ports after reconnects. No configuration, calibration or transcripts are read.
Stop after three minutes without the headset, or terminate this helper process.
"""
import json
import subprocess
import sys
import threading
import urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
ADB=Path.home()/'AppData/Local/Android/Sdk/platform-tools/adb.exe'
SERIAL='2G0YC5ZH0G00HS'
STATUS=ROOT/'build/local-services-status.json'
def start_keeper():
    return subprocess.Popen(['wsl','-d','Ubuntu','--','journalctl','-f','-u','naret-asr','-u','naret-dialogue','-u','naret-ccbm','-u','naret-interpreter','--no-pager','-n','0'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
def adb(args):
    try:
        return subprocess.run([str(ADB),*args],capture_output=True,text=True,timeout=10)
    except (OSError,subprocess.TimeoutExpired):
        return subprocess.CompletedProcess(args,1,'','')
keeper=start_keeper()
missing=0
try:
    while True:
        if keeper.poll() is not None:
            keeper=start_keeper()
        device=adb(['devices'])
        connected=SERIAL+'\tdevice' in device.stdout
        missing=0 if connected else missing+1
        if connected:
            forwards=adb(['-s',SERIAL,'reverse','--list'])
            for port in (8766,8767,8768):
                if f'tcp:{port} tcp:{port}' not in forwards.stdout:
                    adb(['-s',SERIAL,'reverse',f'tcp:{port}',f'tcp:{port}'])
        health={}
        for name,url in [('asr','http://127.0.0.1:8767/'),('dialogue','http://127.0.0.1:8768/health')]:
            try:
                with urllib.request.urlopen(url,timeout=2) as response:
                    health[name]=response.status==200
            except OSError:
                health[name]=False
        STATUS.write_text(json.dumps(dict(headset_connected=connected,services=health,keeper_running=True),indent=2),encoding='utf-8')
        if missing>=36 and '--stay' not in sys.argv:
            break
        threading.Event().wait(5)
finally:
    keeper.terminate()
    STATUS.write_text(json.dumps(dict(keeper_running=False)),encoding='utf-8')
