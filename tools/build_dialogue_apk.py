"""Bounded Windows export, temporarily excluding the blocked desktop detector."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path.home() / 'Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe'

if __name__ == '__main__':
    env = os.environ.copy()
    env['ANDROID_HOME'] = str(Path.home() / 'AppData/Local/Android/Sdk')
    env['JAVA_HOME'] = r'C:\Program Files\Android\Android Studio\jbr'
    extensions = ROOT / '.godot/extension_list.cfg'
    original = extensions.read_bytes()
    try:
        extensions.write_text('res://addons/godotopenxrvendors/plugin.gdextension\n')
        result = subprocess.run([str(GODOT), '--headless', '--xr-mode', 'off', '--audio-driver', 'Dummy', '--path', str(ROOT), '--export-debug', 'Meta Quest 3', 'build/naret-natural-coach-20261009.apk'], env=env, capture_output=True, text=True, timeout=600)
        (ROOT / 'build/natural-coach-export.log').write_text(result.stdout, encoding='utf-8')
        (ROOT / 'build/natural-coach-export.err').write_text(result.stderr, encoding='utf-8')
        print(result.stdout[-1500:])
        print(result.stderr[-1500:])
        bad = any(tag in result.stdout + result.stderr for tag in ('SCRIPT ERROR:', 'Parse Error:', 'ERROR:'))
        raise SystemExit(result.returncode or int(bad))
    finally:
        extensions.write_bytes(original)
