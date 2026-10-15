#!/usr/bin/env python3
"""Launch Godot with .env credentials held only in the child environment."""
import argparse
import os
import shutil
import subprocess
from api_common import ROOT, read_key

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--editor", action="store_true")
parser.add_argument("--offline", action="store_true")
args, extra = parser.parse_known_args()
godot = os.environ.get("GODOT") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
env = os.environ.copy()
if args.offline:
    env.pop("UNI_API_KEY", None)
    env.pop("API_SECRET", None)
    env["NARET_OFFLINE"] = "1"
else:
    key = read_key()
    if key:
        env["UNI_API_KEY"] = key
command = [godot, "--path", str(ROOT)]
if args.editor:
    command.append("--editor")
raise SystemExit(subprocess.call(command + extra, env=env))
