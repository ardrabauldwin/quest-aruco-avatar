#!/usr/bin/env python3
"""Listen back to every baked clip with Whisper (Uni API, large-v3) and flag lines
whose transcript drifts from the script: dropped words, a spoken style tag, the
wrong language. Only synthetic training audio leaves the machine.
  python3 tools/check_voices.py [--min 0.8]
"""
from __future__ import annotations

import argparse
import difflib
import json
import re
import unicodedata

import httpx

from api_common import BASE_URL, MODELS, ROOT, read_key


def words(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return " ".join(re.findall(r"[a-z0-9]+", text))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--min", type=float, default=0.8, help="similarity below this is reported")
    args = parser.parse_args()
    key = read_key()
    if not key:
        raise SystemExit("Missing UNI_API_KEY / API_SECRET")
    manifest = json.loads((ROOT / "assets/audio/manifest.json").read_text(encoding="utf-8"))
    flagged = []
    with httpx.Client(headers={"Authorization": "Bearer " + key}, timeout=120) as client:
        for clip in manifest["clips"]:
            audio = (ROOT / "assets/audio" / clip["file"]).read_bytes()
            try:
                response = client.post(BASE_URL + "/audio/transcriptions",
                    data={"model": MODELS["asr"], "language": clip["language"]},
                    files={"file": ("clip.wav", audio, "audio/wav")})
                heard = response.json().get("text", "") if response.status_code == 200 else f"HTTP {response.status_code}"
            except httpx.HTTPError as error:
                heard = type(error).__name__
            score = difflib.SequenceMatcher(None, words(clip["text"]), words(heard)).ratio()
            spoken_tag = bool(re.search(r"\b(panicked|calm|urgent|worried|breathless|pleading|shouting|whisper)\b", heard, re.I))
            mark = "OK " if score >= args.min and not spoken_tag else "BAD"
            print(f"{mark} {score:.2f} {clip['language']}/{clip['key']}: {heard.strip()}", flush=True)
            if mark == "BAD":
                flagged.append(clip["key"])
    print("NARET_CHECK flagged:", " ".join(sorted(set(flagged))) or "none")


if __name__ == "__main__":
    main()
