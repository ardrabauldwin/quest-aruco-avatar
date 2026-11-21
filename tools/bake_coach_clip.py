"""Rebake the clips of one coach step after its text in data/coach_steps.json changed.

Same voices as the existing coach clips: German and Polish from the local Piper voices in
the Ubuntu (WSL) dialogue environment, English from the cloud voice used for live English
speech (tts-1, am_adam). The cloud token comes from the headset's private config on stdin
and is never stored or printed:

  adb exec-out run-as de.uni_greifswald.naret.cprwitness cat files/config.json | python tools/bake_coach_clip.py compressions
  (a line of data/ui_texts.json:  ... | python tools/bake_coach_clip.py ui:coach.scene_unsafe_again)

Each new clip is transcribed back by the cloud Whisper and compared with its text; the
manifest entry is updated so the app finds the clip by its exact text.
"""
import difflib
import json
import re
import subprocess
import sys
import uuid
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import bake_cloud_english_voices as cloud  # noqa: E402

PIPER = {"de": "de_DE-thorsten-medium", "pl": "pl_PL-darkman-medium"}
WSL_PYTHON = "/opt/naret-dialogue/bin/python"
CRLF = "\r\n"


def wsl_path(path: Path) -> str:
    text = str(path.resolve()).replace("\\", "/")
    return "/mnt/" + text[0].lower() + text[2:]


def piper(text: str, language: str, target: Path) -> None:
    code = (
        "import sys\nfrom piper import PiperVoice\nimport wave\n"
        "text = sys.stdin.read()\n"
        "voice = PiperVoice.load('/opt/naret-dialogue/voices/%s.onnx')\n"
        "with wave.open('%s', 'wb') as out:\n    voice.synthesize_wav(text, out)\n" % (PIPER[language], wsl_path(target))
    )
    subprocess.run(["wsl", "-e", WSL_PYTHON, "-c", code], input=text.encode("utf-8"), check=True)


def heard(key: str, wav_bytes: bytes, language: str) -> str:
    boundary = uuid.uuid4().hex
    body = b""
    for name, value in (("model", "large-v3"), ("language", language), ("response_format", "json")):
        body += ("--" + boundary + CRLF + 'Content-Disposition: form-data; name="' + name + '"' + CRLF + CRLF + value + CRLF).encode()
    body += ("--" + boundary + CRLF + 'Content-Disposition: form-data; name="file"; filename="s.wav"' + CRLF
             + "Content-Type: audio/wav" + CRLF + CRLF).encode() + wav_bytes + (CRLF + "--" + boundary + "--" + CRLF).encode()
    import urllib.request
    request = urllib.request.Request(cloud.BASE + "/audio/transcriptions", data=body,
                                     headers={"Authorization": "Bearer " + key, "Content-Type": "multipart/form-data; boundary=" + boundary})
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.load(response).get("text", "")


def words(text: str) -> str:
    return re.sub(r"[^\w ]", "", text.lower()).strip()


def main() -> None:
    # A coach step ("compressions"), or with "ui:" a line of data/ui_texts.json
    # ("ui:coach.scene_unsafe_again", recorded as coach_scene_unsafe_again.wav).
    step = sys.argv[1]
    key = json.load(sys.stdin)["api"]["api_key"]
    if step.startswith("ui:"):
        ui = json.loads((ROOT / "data/ui_texts.json").read_text(encoding="utf-8-sig"))["strings"]
        name = step[3:]
        guide = {language: {name.replace(".", "_"): ui[language][name]} for language in ["de", "pl", "en"]}
        step = name.replace(".", "_")
    else:
        guide = json.loads((ROOT / "data/coach_steps.json").read_text(encoding="utf-8-sig"))
    manifest_path = ROOT / "assets/audio/coaching/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    for language in ["de", "pl", "en"]:
        text = guide[language][step]
        target = ROOT / "assets/audio/coaching" / language / (step + ".wav")
        if language == "en":
            target.write_bytes(cloud.finalise_wav(cloud.speak(key, text, cloud.VOICES["instructor"])))
        else:
            piper(text, language, target)
        data = target.read_bytes()
        with wave.open(str(target), "rb") as clip:
            duration = clip.getnframes() / clip.getframerate()
        match = difflib.SequenceMatcher(None, words(text), words(heard(key, data, language))).ratio()
        print("%s %s: %.1f s, whisper match %.2f" % (language, step, duration, match), flush=True)
        res_path = "res://assets/audio/coaching/%s/%s.wav" % (language, step)
        for clip in manifest["clips"]:
            if clip["path"] == res_path:
                clip["text"] = text
                break
        else:
            manifest["clips"].append({"text": text, "language": language, "path": res_path})
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("manifest updated")


if __name__ == "__main__":
    main()
