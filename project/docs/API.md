# Uni ApphubAI: configuration and verified behavior

The Godot runtime uses `HTTPRequest` with TLS verification, asynchronous worker threads, four reusable service request nodes, an 8 MiB response bound and a maximum **2-second request deadline**. It does not use an OpenAI SDK or run any AI model on Quest. One request per service can be in flight; the orchestrator queues up to four dialogue requests and starts them at least 500 ms apart. Audio preloads the next responses into a bounded queue and alternates two playback nodes. Request nodes are reused, but persistent HTTP connection pooling depends on Godot's HTTPRequest implementation; it is not claimed or benchmarked here.

## Sprachmodus und Sprecherrolle

`speak(text, language, clip_key, speaker)` trägt seit dem Eigensprache-Modus eine explizite Sprecherrolle (`instructor` oder `bystander`). Vorher wurde am Sprachvergleich unterschieden, wer redet — das bricht, sobald Anweisung und Angehörige dieselbe Sprache sprechen. `utterance_started` gibt die Rolle mit aus; die Hauptszene entscheidet daran, ob der Text als Anweisung oder als Angehörigen-Dialog erscheint und ob die Figur den Mund bewegt.

`bystander_language()` in der Hauptszene ist die einzige Stelle, die den Modus in eine Sprache übersetzt: im Eigensprache-Modus die Sprache des Lernenden, sonst die andere. ASR-Sprache, TTS-Sprache, LLM-Kontext und Offline-Clip-Auswahl folgen alle dieser einen Funktion.

## Credentials

Desktop development:

```sh
cp .env.example .env
# Set UNI_API_KEY, or keep an existing API_SECRET, privately in .env.
python3 tools/run_local.py --editor
python3 tools/run_local.py
python3 tools/run_local.py --offline
```

`run_local.py` parses only those two dotenv keys as data and passes the credential only through the child process environment. It never shells/sources `.env`. Godot does not read the repository's `.env`, which is excluded from Git and export.

On a provisioned headset, put a private `config.json` with the structure of [`config.example.json`](../config.example.json) in Godot's `user://` application directory. API keys resolve in order: process `UNI_API_KEY`, process `API_SECRET`, then `user://config.json` → `api.api_key`. Runtime configuration is private installation data, never a project resource. The app uses offline replies when no key is set. `api.offline: true` or `NARET_OFFLINE=1` forces offline mode. This development scaffold has no secure enrollment/backend token broker; production deployment should provision short-lived scoped credentials.

## Live verification on 2026-09-08

[`api_probe.json`](api_probe.json) contains sanitized results from actual requests using synthetic text/audio. No API key, recorded user speech, raw response text or authorization header is written to the report.

| Check | Actual result | Observed latency |
| --- | --- | --- |
| `/models` | All four requested models listed | 597 ms |
| `omnivoice`, German | HTTP 200, valid WAV | 589 ms |
| `omnivoice`, Polish | HTTP 200, valid WAV | 551 ms |
| Requested Qwen chat model | HTTP 200, completion returned | 736 ms |
| `large-v3`, synthetic German speech | HTTP 200, nonempty transcript | 619 ms |

**Omnivoice is present and works. Omit `voice`.** The common OpenAI example `voice: "alloy"` and `voice: "default"` returned backend HTTP 500. The working body is:

```json
{"model":"omnivoice","input":"Zachowam spokój. Pomogę pani.","response_format":"wav"}
```

The request/list identifier is `unsloth/Qwen3.8-27B-GGUF:Q4_K_M`. The server's returned `model` string is `unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M`. The app sends the exact requested identifier and makes no model substitutions; this server routing/name discrepancy is preserved in the probe report. `/models` is checked at startup; models absent from a successfully retrieved list are disabled. A failed listing check does not prove a model is unavailable, so the configured model may still be attempted with the same 2-second bound.

A separate [Godot runtime probe](godot_api_probe.json) also passed with real HTTPRequest multipart upload, WAV decoding and strict DE/PL JSON parsing: ASR 975 ms, LLM DE/PL 1392/1089 ms, TTS DE/PL 1174/829 ms. Reproduce with `python3 tools/run_local.py --headless --xr-mode off --script tools/probe_runtime.gd`.

These are individual workstation measurements, not latency guarantees or Quest benchmarks. The TTS samples exceed the brief's 500 ms target. ASR + LLM + TTS has up to three separate 2-second deadlines; the entire conversation is not promised to finish in 2 seconds. The probe itself waits up to 30 seconds to distinguish service availability from runtime latency requirements.

## Speech and offline behavior

Hold the push-to-talk input to record; release to transcribe. Recording is capped at 12 seconds, uses an isolated muted capture bus and encodes PCM16 WAV in memory. No speech recording file is stored. `recording_changed` reports actual capture transitions, including duration expiry and failed permission/input requests. Android microphone permission is requested on first use; if permission is newly granted, press push-to-talk again. `audio/driver/enable_input` must be enabled in the project and the exported Android app requires recording and internet permissions.

With no ASR service, use the phrase buttons or typed desktop transcript. There is **no offline speech recognition**. Missing/slow LLM calls produce deterministic German/Polish bystander responses. `cancel_pending()` invalidates queued and in-flight dialogue generations on language changes or scenario restart. Scripted responses play the matching local clip immediately. Failed cloud TTS decodes to a local fallback clip; `utterance_started` carries the exact spoken fallback text, allowing captions to stay truthful. The twenty bundled WAVs include reassurance, calling help, fetching the AED, thanks and basic scenario instructions in both languages.

Bystander replies are parsed only as JSON. Accepted action labels are `calm`, `call_help`, `fetch_aed`, `thank`, `none`; text length and language are validated, all other fields are dropped. These labels describe simulated bystander behavior. They never invoke code, call emergency services, administer treatment or mutate clinical scenario state. The scenario controller exclusively owns training progression.

## Verification

```sh
godot --headless --xr-mode off --editor --path . --import --quit
godot --headless --xr-mode off --path . --script tests/run_tests.gd
```

The local checks cover allowlisted parsing, malicious/extra fields, wrong languages, malformed responses, DE/PL deterministic actions, negation, PCM WAV header/decode the presence of every offline clip, cancellation of stale responses, a strict 500 ms request interval and microphone UI reset when input is disabled. Headset microphone capture, Wi-Fi latency under load and hardware audio output still require device validation.
