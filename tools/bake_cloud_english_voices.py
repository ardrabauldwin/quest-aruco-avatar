#!/usr/bin/env python3
"""Regenerate every saved English line with the two cloud voices used for live English speech.

Saved lines and generated answers then share one voice per person: the instructor uses
am_adam and Anna uses af_sky. These voices are English only. German and Polish clips stay.

Reads the app configuration JSON from stdin, so the token is never stored or printed:
  adb exec-out run-as <package> cat files/config.json | python tools/bake_cloud_english_voices.py
"""
import difflib
import hashlib
import json
import re
import sys
import urllib.request
import uuid
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "https://apphubai.wolke.uni-greifswald.de/v1"
VOICES = {"instructor": "am_adam", "anna": "af_sky", "bystander": "af_sky"}
CRLF = "\r\n"


def speak(key: str, text: str, voice: str) -> bytes:
    body = json.dumps({"model": "tts-1", "input": text, "response_format": "wav", "voice": voice}).encode()
    request = urllib.request.Request(BASE + "/audio/speech", data=body,
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read()
            if data[:4] == b"RIFF":
                return data
        except OSError as error:
            if attempt == 2:
                raise RuntimeError(str(error)[:80])
    raise RuntimeError("no WAV returned")


def heard(key: str, wav_bytes: bytes) -> str:
    boundary = uuid.uuid4().hex
    body = b""
    for name, value in (("model", "large-v3"), ("language", "en"), ("response_format", "json")):
        body += ("--" + boundary + CRLF + 'Content-Disposition: form-data; name="' + name + '"' + CRLF + CRLF + value + CRLF).encode()
    body += ("--" + boundary + CRLF + 'Content-Disposition: form-data; name="file"; filename="s.wav"' + CRLF
        + "Content-Type: audio/wav" + CRLF + CRLF).encode() + wav_bytes + (CRLF + "--" + boundary + "--" + CRLF).encode()
    request = urllib.request.Request(BASE + "/audio/transcriptions", data=body,
        headers={"Authorization": "Bearer " + key, "Content-Type": "multipart/form-data; boundary=" + boundary})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response).get("text", "")


def words(text: str) -> str:
    return re.sub(r"[^a-z0-9 ]", "", text.lower()).strip()


def finalise_wav(data: bytes) -> bytes:
    """The cloud streams WAV with 0xFFFFFFFF RIFF/data sizes, which Godot's importer and the
    Android export cannot read (2026-11-02 and 11-04). Write the real sizes."""
    data = bytearray(data)
    at = 12
    while at + 8 <= len(data):
        chunk, size = bytes(data[at:at + 4]), int.from_bytes(data[at + 4:at + 8], "little")
        if chunk == b"data":
            length = len(data) - at - 8
            if length % 2:
                length -= 1
                del data[at + 8 + length:]
            data[at + 4:at + 8] = length.to_bytes(4, "little")
            break
        at += 8 + size + (size % 2)
    data[4:8] = (len(data) - 8).to_bytes(4, "little")
    return bytes(data)


def make(key: str, path: Path, text: str, speaker: str) -> float:
    data = finalise_wav(speak(key, text, VOICES[speaker]))
    path.write_bytes(data)
    match = difflib.SequenceMatcher(None, words(text), words(heard(key, data))).ratio()
    with wave.open(str(path), "rb") as clip:
        duration = clip.getnframes() / clip.getframerate()
    print(f"{match:.2f} {speaker:10} {path.name}", flush=True)
    return duration


def main() -> None:
    key = json.load(sys.stdin)["api"]["api_key"]
    path = ROOT / "assets/audio/manifest.json"
    raw = path.read_bytes()
    bom = raw.startswith(b"\xef\xbb\xbf")
    source = raw.decode("utf-8-sig")
    for clip in [c for c in json.loads(source)["clips"] if c["language"] == "en"]:
        target = ROOT / "assets/audio" / clip["file"]
        duration = make(key, target, clip["text"], clip["speaker"])
        start = source.index('"file":  "%s"' % clip["file"])
        end = source.index("}", start)
        block = re.sub(r'("duration_s":\s+)[\d.]+', lambda m: m.group(1) + str(round(duration, 3)), source[start:end])
        block = block.replace(clip["sha256"], hashlib.sha256(target.read_bytes()).hexdigest())
        source = source[:start] + block + source[end:]
    json.loads(source)
    path.write_bytes((b"\xef\xbb\xbf" if bom else b"") + source.encode("utf-8"))

    coaching = json.loads((ROOT / "assets/audio/coaching/manifest.json").read_text(encoding="utf-8"))
    for clip in [c for c in coaching["clips"] if c["language"] == "en"]:
        make(key, ROOT / clip["path"].replace("res://", ""), clip["text"], "instructor")

    path = ROOT / "assets/audio/confirmation/manifest.json"
    confirmation = json.loads(path.read_text(encoding="utf-8"))
    for clip in [c for c in confirmation["clips"] if c["language"] == "en"]:
        clip["duration_s"] = round(make(key, ROOT / clip["path"].replace("res://", ""), clip["text"], "instructor"), 3)
        clip["model"] = "tts-1:" + VOICES["instructor"]
    path.write_text(json.dumps(confirmation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
