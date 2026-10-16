"""Run app unit tests without the Windows-blocked native addon.

This checks application logic only; it is not a detector validation.
Restore the extension list even if Godot times out.
"""
from pathlib import Path
import subprocess

project = Path(__file__).resolve().parents[1]
extension_list = project / ".godot/extension_list.cfg"
original = extension_list.read_bytes()
godot = Path(r"C:\Users\bauld\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe")
try:
    extension_list.write_text("res://addons/godotopenxrvendors/plugin.gdextension\n")
    result = subprocess.run(
        [str(godot), "--headless", "--xr-mode", "off", "--audio-driver",
         "Dummy", "--path", str(project), "--script", "tests/run_tests.gd"],
        capture_output=True, text=True, timeout=180,
    )
    (project / "build/addon-unit-tests.log").write_text(result.stdout)
    (project / "build/addon-unit-tests.err").write_text(result.stderr)
    print(result.stdout[-2200:])
    print(result.stderr[-2200:])
    bad_log = any(tag in result.stdout + result.stderr
                  for tag in ("SCRIPT ERROR:", "Parse Error:", "ERROR:"))
    raise SystemExit(result.returncode or int(bad_log))
finally:
    extension_list.write_bytes(original)
