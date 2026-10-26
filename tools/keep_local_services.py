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
import time
import msvcrt
import urllib.request
from pathlib import Path
from usb_bridge_recovery import quest_usb_present, should_recover, speech_bridge_healthy, repair_speech_bridge

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
# One keeper owns reconnect recovery; duplicate helpers must not restart ADB
# underneath each other.
lock_file=(ROOT/'build/local-services-keeper.lock').open('a+b')
lock_file.seek(0)
if not lock_file.read(1):
    lock_file.write(b'0'); lock_file.flush()
lock_file.seek(0)
try:
    msvcrt.locking(lock_file.fileno(),msvcrt.LK_NBLCK,1)
except OSError:
    raise SystemExit(0)
keeper=start_keeper()
missing=0
last_bridge_reset=-120.0
bridge_recoveries=0
speech_bridge_recoveries=0
speech_path=None
speech_path_failures=0
last_speech_check=-30.0
try:
    while True:
        if keeper.poll() is not None:
            keeper=start_keeper()
        device=adb(['devices'])
        connected=SERIAL+'\tdevice' in device.stdout
        missing=0 if connected else missing+1
        elapsed=time.monotonic()-last_bridge_reset
        # A first reset can fail while the physical USB interface is still
        # present. Keep bounded recovery attempts instead of permanently
        # disarming recovery until a manual reconnect succeeds.
        if (not connected and missing>=2 and elapsed>=20
                and '\tdevice' not in device.stdout and '\tunauthorized' not in device.stdout
                and should_recover(device.stdout,missing,elapsed,quest_usb_present())):
            adb(['kill-server'])
            adb(['start-server'])
            last_bridge_reset=time.monotonic()
            bridge_recoveries+=1
            device=adb(['devices'])
            connected=SERIAL+'\tdevice' in device.stdout
            if connected: missing=0
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
        if connected and health.get('asr') and time.monotonic()-last_speech_check>=30:
            speech_path=speech_bridge_healthy(adb,SERIAL)
            speech_path_failures=0 if speech_path else speech_path_failures+1
            if speech_path_failures>=2:
                if repair_speech_bridge(adb,SERIAL):
                    speech_bridge_recoveries+=1
                    speech_path=speech_bridge_healthy(adb,SERIAL)
                speech_path_failures=0
            last_speech_check=time.monotonic()
        if not connected:
            speech_path=None
            speech_path_failures=0
        STATUS.write_text(json.dumps(dict(headset_connected=connected,services=health,keeper_running=True,bridge_recoveries=bridge_recoveries,speech_bridge_healthy=speech_path,speech_bridge_recoveries=speech_bridge_recoveries),indent=2),encoding='utf-8')
        if missing>=36 and '--stay' not in sys.argv:
            break
        threading.Event().wait(5)
finally:
    keeper.terminate()
    STATUS.write_text(json.dumps(dict(keeper_running=False)),encoding='utf-8')
