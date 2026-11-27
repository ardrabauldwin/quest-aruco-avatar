"""Bake the issue #1 scene lines that have no clip yet, so they also play offline:

  * the dispatcher (Situation A) and the ambulance crew, each with a voice of its own
    (texts from build/tmp/scene_lines.json, dumped by build/tmp/dump_scene_lines.gd);
  * Anna's 112 line in the website's wording (her "help" clip);
  * instructor lines of data/ui_texts.json whose clip is missing or out of date.

German and Polish from the local Piper voices (WSL), English from the cloud voices. The
cloud token comes from the headset's private config on stdin and is never stored or printed:

  adb exec-out run-as de.uni_greifswald.naret.cprwitness cat files/config.json | python tools/bake_scene_lines.py

Each clip is transcribed back by the cloud Whisper and compared with its text.
"""
import difflib
import hashlib
import json
import subprocess
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import bake_coach_clip as coach  # noqa: E402

# Piper voice per (role, language); English cloud voice per role.
PIPER = {
    "instructor": {"de": "de_DE-thorsten-medium", "pl": "pl_PL-darkman-medium"},
    "dispatcher": {"de": "de_DE-kerstin-low", "pl": "pl_PL-gosia-medium"},
    "ems": {"de": "de_DE-thorsten-medium", "pl": "pl_PL-darkman-medium"},
    "anna": {"de": "de_DE-kerstin-low", "pl": "pl_PL-gosia-medium"},
}
CLOUD = {"instructor": "am_adam", "dispatcher": "af_sarah", "ems": "am_michael", "anna": "af_sky"}
UI_KEYS = ["coach.look_left_right", "coach.tell_if_safe", "coach.safety_key", "coach.pause_too_long"]


def piper(text: str, voice: str, target: Path) -> None:
    code = (
        "import sys\nfrom piper import PiperVoice\nimport wave\n"
        "text = sys.stdin.read()\n"
        "voice = PiperVoice.load('/opt/naret-dialogue/voices/%s.onnx')\n"
        "with wave.open('%s', 'wb') as out:\n    voice.synthesize_wav(text, out)\n" % (voice, coach.wsl_path(target))
    )
    subprocess.run(["wsl", "-e", coach.WSL_PYTHON, "-c", code], input=text.encode("utf-8"), check=True)


def bake(key: str, role: str, language: str, text: str, target: Path) -> float:
    target.parent.mkdir(parents=True, exist_ok=True)
    if language == "en":
        target.write_bytes(coach.cloud.finalise_wav(coach.cloud.speak(key, text, CLOUD[role])))
    else:
        piper(text, PIPER[role][language], target)
    data = target.read_bytes()
    with wave.open(str(target), "rb") as clip:
        duration = clip.getnframes() / clip.getframerate()
    match = difflib.SequenceMatcher(None, coach.words(text), coach.words(coach.heard(key, data, language))).ratio()
    print("%-10s %s %-22s %.1f s, whisper match %.2f" % (role, language, target.name, duration, match), flush=True)
    return duration


def main() -> None:
    key = json.load(sys.stdin)["api"]["api_key"]
    coaching_path = ROOT / "assets/audio/coaching/manifest.json"
    coaching = json.loads(coaching_path.read_text(encoding="utf-8-sig"))

    def put(entry: dict) -> None:
        for clip in coaching["clips"]:
            if clip["path"] == entry["path"]:
                clip.clear()
                clip.update(entry)
                return
        coaching["clips"].append(entry)

    scene = json.loads((ROOT / "build/tmp/scene_lines.json").read_text(encoding="utf-8"))
    for role, lines in scene.items():
        for name, texts in lines.items():
            for language in ["de", "pl", "en"]:
                text = texts[language]
                target = ROOT / "assets/audio/coaching" / language / ("%s_%s.wav" % (role, name))
                bake(key, role, language, text, target)
                put({"text": text, "language": language, "speaker": role,
                     "path": "res://assets/audio/coaching/%s/%s_%s.wav" % (language, role, name)})

    ui = json.loads((ROOT / "data/ui_texts.json").read_text(encoding="utf-8-sig"))["strings"]
    for name in UI_KEYS:
        for language in ["de", "pl", "en"]:
            text = ui[language][name]
            file = name.replace(".", "_") + ".wav"
            bake(key, "instructor", language, text, ROOT / "assets/audio/coaching" / language / file)
            put({"text": text, "language": language, "path": "res://assets/audio/coaching/%s/%s" % (language, file)})
    coaching_path.write_text(json.dumps(coaching, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    offline_path = ROOT / "assets/audio/manifest.json"
    offline = json.loads(offline_path.read_text(encoding="utf-8-sig"))
    for language in ["de", "pl", "en"]:
        text = ui[language]["anna.calling_112"]
        target = ROOT / "assets/audio" / ("tts_" + language) / "help.wav"
        duration = bake(key, "anna", language, text, target)
        for item in offline["clips"]:
            if item["key"] == "help" and item["language"] == language:
                item.update({"text": text, "duration_s": round(duration, 3),
                             "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                             "generator": "tts-1:" + CLOUD["anna"] if language == "en" else "piper:" + PIPER["anna"][language]})
    offline_path.write_text(json.dumps(offline, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("manifests updated")


if __name__ == "__main__":
    main()
