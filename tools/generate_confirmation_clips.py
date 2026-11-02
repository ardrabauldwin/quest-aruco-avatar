"""Generate exact-text offline confirmations with the installed local Piper voices.

Run using the Piper environment, e.g. /opt/naret-dialogue/bin/python in WSL.
Only synthesizes files; never plays audio or contacts an external service.
"""
import json
from pathlib import Path
import re
import shutil
import wave
from local_dialogue_server import speech, VOICE_ROOT, VOICES

ROOT = Path(__file__).resolve().parents[1]


def main():
    source = (ROOT / "scripts/scenario/speech_confirmation.gd").read_text(encoding="utf-8")
    # The localized question tables are literal JSON dictionaries in GDScript.
    tables = {language: json.loads(table) for language, table in
              re.findall(r'"(en|de|pl)": (\{[^\n]+\})', source)}
    repeat = json.loads(re.search(r'return (\{"en":.*?\})\.get\(language,', source)[1])
    assert set(tables) == {"en", "de", "pl"}
    clips = []
    output = ROOT / "assets/audio/confirmation"
    for language, table in tables.items():
        assert set(table) == {"begin_check", "check_responsiveness", "check_breathing", "ventilation", "pair"}
        folder = output / language
        folder.mkdir(parents=True, exist_ok=True)
        model = VOICES[(language, "instructor")]
        shutil.copyfile(VOICE_ROOT / (model + "-MODEL_CARD"), folder / "PIPER_MODEL_CARD.txt")
        for key, text in {**table, "repeat": repeat[language]}.items():
            path = folder / (key + ".wav")
            path.write_bytes(speech({"input": text, "language": language, "speaker": "instructor"}))
            with wave.open(str(path), "rb") as wav:
                assert wav.getnframes() > 0
                duration = wav.getnframes() / wav.getframerate()
            clips.append({"text": text, "language": language, "speaker": "instructor",
                          "path": "res://" + path.relative_to(ROOT).as_posix(),
                          "model": model, "duration_s": round(duration, 3)})
            print(language, key, round(duration, 2), flush=True)
    (output / "manifest.json").write_text(json.dumps({"generator": "Piper (local)", "clips": clips},
        ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
