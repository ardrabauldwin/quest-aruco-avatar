"""Stage the user's existing native Android detector and matching XR addon.

Usage: python tools/stage_user_quest.py --source-project ../../project
This copies dependencies; it never imports saved runtime credentials or nudges.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-project', type=Path, required=True)
args = parser.parse_args()
source = args.source_project.resolve()
target = ROOT / 'addons/opencv_aruco/bin'
target.mkdir(parents=True, exist_ok=True)
shutil.copytree(source / 'bin/android', target / 'android', dirs_exist_ok=True)
shutil.copytree(source / 'addons/godotopenxrvendors', ROOT / 'addons/godotopenxrvendors', dirs_exist_ok=True)
lines = []
for line in (source / 'bin/opencv_aruco.gdextension').read_text().splitlines():
    if ' = "./' in line and not (target / line.split('"')[1]).exists():
        continue
    lines.append(line)
(target / 'opencv_aruco.gdextension').write_text('\n'.join(lines) + '\n')
report = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (target / 'android').glob('*.so')}
(ROOT / 'build').mkdir(exist_ok=True)
(ROOT / 'build/native_provenance.json').write_text(json.dumps(report, indent=2) + '\n')
print('Staged user Android detector and XR addon; hashes in build/native_provenance.json')
