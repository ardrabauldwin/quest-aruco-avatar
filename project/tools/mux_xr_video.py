#!/usr/bin/env python3
"""build/<name>/{frames,speech.json} -> build/<name>.mp4: frames at their real
timestamps, the baked voice clips mixed in where the app spoke them."""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAME = sys.argv[1] if len(sys.argv) > 1 else "xr_scenario"
DIR = ROOT / "build" / NAME
log = json.loads((DIR / "speech.json").read_text())
times = log["times"]
start = times[0]
with open(DIR / "frames.txt", "w") as out:
    for i, t in enumerate(times):
        out.write(f"file 'frames/{i:05d}.jpg'\nduration {(times[i + 1] if i + 1 < len(times) else t + 1 / 30) - t:.4f}\n")
clips = {(c["language"], c["text"]): c["file"] for c in json.loads((ROOT / "assets/audio/manifest.json").read_text())["clips"]}
# The app speaks one line at a time and a new step can cut the current one off,
# so each clip ends where the next utterance starts; the AED has its own speaker.
inputs, delays, lengths = [], [], []
speech = sorted(log["speech"], key=lambda e: e["t"])
for i, event in enumerate(speech):
    clip = clips.get((event["language"], event["text"]))
    if clip and event["t"] >= start - 1.0:  # a line may begin a moment before the first frame
        inputs += ["-i", str(ROOT / "assets/audio" / clip)]
        delays.append(max(0, int((event["t"] - start) * 1000)))
        channel = event["speaker"] == "aed"
        later = [e["t"] for e in speech[i + 1:] if (e["speaker"] == "aed") == channel]
        lengths.append(later[0] - event["t"] if later else 60.0)
command = ["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(DIR / "frames.txt")] + inputs
if delays:
    chains = [f"[{i + 1}:a]atrim=0:{lengths[i]:.3f},adelay={d}|{d}[a{i}]" for i, d in enumerate(delays)]
    mix = "".join(f"[a{i}]" for i in range(len(delays))) + f"amix=inputs={len(delays)}:normalize=0[aout]"
    command += ["-filter_complex", ";".join(chains + [mix]), "-map", "0:v", "-map", "[aout]", "-c:a", "aac"]
command += ["-vf", "fps=30", "-c:v", "libx264", "-pix_fmt", "yuv420p", str(ROOT / "build" / f"{NAME}.mp4")]
subprocess.run(command, check=True)
print("NARET_VIDEO", ROOT / "build" / f"{NAME}.mp4", len(times), "frames", len(delays), "voice clips")
