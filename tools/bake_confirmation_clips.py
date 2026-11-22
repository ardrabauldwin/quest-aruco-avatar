"""Rebake the yes/no confirmation questions after their texts in
scripts/ai/speech_pipeline.gd (Confirmation.question) changed.

Same voices as the other instructor clips: German and Polish from the local Piper voices
(WSL), English from the cloud voice (tts-1, am_adam). The cloud token comes from the
headset's private config on stdin and is never stored or printed:

  adb exec-out run-as de.uni_greifswald.naret.cprwitness cat files/config.json | python tools/bake_confirmation_clips.py

Each clip is transcribed back by the cloud Whisper and compared with its text.
"""
import difflib
import json
import re
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import bake_coach_clip as coach  # noqa: E402

KEYS = ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "ventilation", "pair"]


def main() -> None:
    key = json.load(sys.stdin)["api"]["api_key"]
    source = (ROOT / "scripts/ai/speech_pipeline.gd").read_text(encoding="utf-8")
    tables = {language: json.loads(table) for language, table in re.findall(r'"(en|de|pl)": (\{"begin_check"[^\n]+\})', source)}
    assert set(tables) == {"en", "de", "pl"}, tables.keys()
    manifest_path = ROOT / "assets/audio/confirmation/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    for language, table in tables.items():
        for name in KEYS:
            text = table[name]
            target = ROOT / "assets/audio/confirmation" / language / (name + ".wav")
            if language == "en":
                target.write_bytes(coach.cloud.finalise_wav(coach.cloud.speak(key, text, coach.cloud.VOICES["instructor"])))
                model = "tts-1:" + coach.cloud.VOICES["instructor"]
            else:
                coach.piper(text, language, target)
                model = coach.PIPER[language]
            data = target.read_bytes()
            with wave.open(str(target), "rb") as clip:
                duration = clip.getnframes() / clip.getframerate()
            match = difflib.SequenceMatcher(None, coach.words(text), coach.words(coach.heard(key, data, language))).ratio()
            print("%s %s: %.1f s, whisper match %.2f" % (language, name, duration, match), flush=True)
            res_path = "res://assets/audio/confirmation/%s/%s.wav" % (language, name)
            for entry in manifest["clips"]:
                if entry["path"] == res_path:
                    entry.update({"text": text, "model": model, "duration_s": round(duration, 3)})
                    break
            else:
                manifest["clips"].append({"text": text, "language": language, "speaker": "instructor", "path": res_path,
                                          "model": model, "duration_s": round(duration, 3)})
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("manifest updated")


if __name__ == "__main__":
    main()
