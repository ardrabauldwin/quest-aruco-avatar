# Live PC deployment

Version 3 (`Qwen/Qwen3-0.6B` plus `/opt/naret-training/v3-adapter`) is deployed for observation interpretation through the local dialogue backend. The internal worker listens only on `127.0.0.1:8771`. The Quest continues using its existing `127.0.0.1:8768` USB endpoint; no APK update is required.

Anna/instructor generated conversation remains `qwen3:4b-instruct` via Ollama. Whisper remains large-v3-turbo. Piper voices, calibration, placement and counting are unchanged by this deployment. CCBM and scenario allowed-action guards remain downstream of the interpreter.

Serving replay: 30/36 exact labels, zero false progression proposals on the already-inspected version 3 synthetic set. See `serving_check.json`. This is a deployment regression check, not new independent student validation or proof that this model is universally best. Selection prioritised version 3's original zero-false-proposal fresh-set result; versions 4/5 were not consistently better.

The actual live route was checked with a completed abnormal-breathing report and a future breath intention. The Quest was disconnected at deployment, so physical headset verification is pending. PC inference can still take several seconds; this deployment does not solve Whisper's CPU latency.

WSL systemd service: `naret-interpreter`. Routing drop-in: `/etc/systemd/system/naret-dialogue.service.d/observation-interpreter.conf`. Output structure, label enums and quoted evidence are checked before replying; invalid inference is returned as an error rather than silently advancing the scenario.

For PC session availability run `python tools/keep_local_services.py --stay` from the app directory. The helper keeps WSL running and restores USB forwards when the Quest reconnects. It is currently running in the background; a PC reboot will require starting it again.

Rollback: set the routing drop-in's `NARET_INTERPRETER_URL` environment value to an empty string, reload systemd and restart `naret-dialogue`. That returns observation interpretation to the unchanged Ollama model. The adapter files and previous experiments remain available.
