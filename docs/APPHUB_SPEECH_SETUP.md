# AppHub speech recognition

The APK supports university Whisper `large-v3` through
`https://apphubai.wolke.uni-greifswald.de/v1/audio/transcriptions`.
Recordings are encoded as WAV in memory and sent with the selected EN/DE/PL
language. API tokens are configured separately; none belongs in the APK or Git.

1. Sign in at https://apphub.wolke.uni-greifswald.de/ai/access and get an API token.
2. Run `python tools/save_apphub_token.py` to save it locally in the Git-ignored
   `project/.env`, or set the `UNI_API_KEY` environment variable yourself.
3. Install the matching debug APK on your USB-connected Quest. From `project/`:

   ```powershell
   python tools/configure_quest.py --speech-only --asr-timeout 0 --adb "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
   ```

4. Restart the app, select the language and test a short completed report.

The speech-only option clears the local ASR override while preserving dialogue,
TTS, CCBM and unrelated settings. It does not overwrite calibration files. Private
device configuration is transferred over stdin with the existing provisioner.

## Unlimited recognition wait

`asr_timeout_s=0` (the new default) disables the app's automatic cloud transcription
deadline. It does not deliberately delay a reply: a received result is handled
immediately. Network/server errors can still end a request. A server that never
responds can otherwise leave recognition waiting; Restart cancels the request and
discards the old session's result. HTTP I/O remains asynchronous.

For an optional finite deadline, provision with `--asr-timeout 60` (seconds).
Existing device configurations keep their explicit timeout until reconfigured;
re-run the command above to replace an earlier 20-second setting with unlimited.
The cloud setting does not alter the separate local-PC ASR retry deadlines or
the short dialogue/TTS fallbacks. Unlimited waiting is not faster recognition.

Godot timeout reference:
https://docs.godotengine.org/en/stable/classes/class_httprequest.html#class-httprequest-property-timeout

## What still needs the PC

This switch changes speech recognition only. Existing local dialogue/TTS and the
external CCBM worker still require their configured services. Bundled recordings
can play without live TTS. Sharing an APK does not share credentials or configure
another person's PC.

Offline provisioning checks: `python tools/test_apphub_speech_config.py`.
Godot tests include a stalled HTTP endpoint that verifies an unlimited request
can be cancelled and a fresh request can succeed. These tests do not validate
Quest camera detection, hand tracking, floor placement or live speech accuracy.
