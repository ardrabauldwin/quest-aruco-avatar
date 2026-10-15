"""Bounded integration check without the unavailable Windows detector."""
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
godot=Path.home()/'Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe'
extensions=ROOT/'.godot/extension_list.cfg'
original=extensions.read_bytes()
try:
    extensions.write_text('res://addons/godotopenxrvendors/plugin.gdextension\n')
    result=subprocess.run([str(godot),'--headless','--xr-mode','off','--audio-driver','Dummy','--path',str(ROOT),'--script','tools/check_ccbm_live.gd'],capture_output=True,text=True,timeout=90)
    output=result.stdout+result.stderr
    print(output)
    raise SystemExit(result.returncode or int(any(tag in output for tag in ('SCRIPT ERROR:','Parse Error:','ERROR:'))))
finally:
    extensions.write_bytes(original)
