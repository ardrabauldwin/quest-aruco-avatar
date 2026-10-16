# Offline speech

All speech is pre-baked WAV, one folder per language. Texts, speakers, durations and SHA-256 values are in [manifest.json](manifest.json). Playback needs no network and no local AI model.

The texts live in `data/instructor_lines.json` (instructor) and `data/bystander_lines.json` (Drehbuch lines of Anna, Marek and the AED). They are spoken with Fish Audio S2 Pro, each role cloning a fixed reference voice that the model invented itself (`data/voices/`), not a recording of a real person:

```sh
~/Projects/fish-speech/.venv/bin/python tools/generate_voices_fish.py --bake
python3 tools/check_voices.py   # Whisper check: every clip says its text
```

Fish Audio Research License: research and non-commercial use only. Subtitles always follow the clip actually played.
