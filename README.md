# NaReT ? current private source snapshot

Current local app source and additions, shared for review on 15 October 2026.

This repository contains browseable source files, not just an APK or ZIP. It combines Denis?s NaReT foundation with Ardra?s current integration work. Original authorship and licensing still apply; this snapshot does not recreate development history.

## Start here

- `scripts/main.gd`: app wiring, dialogue, progression and character placement.
- `scripts/tracking/`: marker fusion, startup placement, viewer gate and spatial alignment.
- `scripts/ai/`: microphone/audio handling, conversation and observation interpretation.
- `scripts/scenario/ccbm_bridge.gd`: observation-to-CCBM integration.
- `integrations/ccbm/`: PDDL model, observation callbacks and native engine wrapper.
- `integrations/finetuning/`: interpreter training/serving scripts and synthetic development data.
- `scenes/main.tscn`: patient, Anna and instructor scene composition.
- `tools/local_dialogue_server.py`: PC-side dialogue and speech service.

## Important differences from the APK release

The APK release is the latest existing binary, built 13 October 2026. This source snapshot includes current workspace edits; do not assume it is byte-for-byte the source used for that older binary. No new APK was built by publishing this snapshot.

The local export helper uses Godot 4.7.1. Some inherited documentation mentions other versions or older app behaviour. See `UPSTREAM_README.md` for historical setup information.

## Dependencies and configuration

`tools/setup_dependencies.py`, `.gitmodules` and `docs/TRACKING.md` describe external dependencies. OpenXR vendor/native detector binaries and large model weights are not bundled in this source upload. The small `addons/naret_upstream` runtime sources needed by the current app are included.

API credentials, device calibration, microphone/session recordings, machine-local build outputs and recovered real-transcript training experiments are excluded. Configure private settings separately. The excluded v5 experiment files mean those experiments are not fully reproducible from this snapshot alone.

Live speech, generated conversation and CCBM currently require configured PC services; the APK is not a self-contained offline AI deployment. Character placement, speech interpretation and latency still have known limitations. The standalone experimental sensor/audio recorder discussed for the study has not yet been implemented.
