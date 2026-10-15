# USB-local speech prototype

The headset microphone sends WAV recordings over USB to whisper.cpp v1.8.2,
running as the unprivileged `naret-asr` WSL user. Its multilingual `medium` model
supports the selected English, German or Polish language. No university key is
needed. The server binds only to PC loopback; `adb reverse` connects the Quest.

Start the recogniser on this PC:

```powershell
wsl -d Ubuntu -u naret-asr -- bash /mnt/c/Users/bauld/Overlay/quest-aruco-avatar/builds/naret-migration/tools/start_local_asr.sh
python tools/connect_local_speech.py
```

The CCBM worker must also run on PC port 8766. Restart the headset app after
configuration. Choose English and start training. Tap Microphone ON, wait briefly,
speak one report, then tap Microphone OFF to submit. Wait for confirmation:
“The scene is safe”, “He is not responding”, “Anna, please call 112”,
“He is not breathing normally”. Physical compressions remain hand-tracked.

Recognised text uses the existing conservative phrase grammar and real CCBM
worker. Anna uses bundled recordings and scripted fallback replies. This adds
speech recognition, not a local language model: arbitrary wording is not
guaranteed to advance the exercise. Spoken reports do not verify physical checks.

English now accepts explicit alternatives such as “He isn't responding”,
“No response”, and “He isn't breathing normally”. A small list of ambiguous
reports asks a specific recorded confirmation question. Say “yes” or “no” after
the question finishes, using the microphone button again. A confirmation lasts
30 seconds and is cleared by a new utterance, stage change, reset or language
change. A bare yes without a pending question cannot advance. Unrelated speech
and opposite findings are never guessed into an accepted report. CCBM and the
existing scenario guards still check all proposed actions.

USB and both PC workers are required. The local recognition deadline is 30 s;
the existing cloud request settings remain unchanged. Recognition accuracy and
microphone quality must still be checked with actual learner speech. The server
can write temporary conversion files and diagnostic transcripts on this PC;
do not treat this development server as a production recording/privacy system.

Source: https://github.com/ggml-org/whisper.cpp/tree/v1.8.2/examples/server
