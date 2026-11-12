# NaReT · Mannequin XR (CPR Witness)

Mixed-reality CPR training for **Meta Quest 3**, built with **Godot 4.7.2,
OpenXR and GDScript**. A virtual patient is overlaid on a real CPR manikin
and one virtual witness, Anna, stands in the room. The trainee works through
adult BLS following ERC 2025, mostly **by voice**, in **German or Polish**.
Anna can speak the trainee's language or the neighbouring one.

This branch (`naret-combined`) combines Denis's NaReT foundation (patient,
witness, language, interface, scenario) with Ardra's tracking work: the
marker camera worker, three-marker fusion, startup placement, viewer-motion
gate and hand compression counting. Original authorship and licences still
apply.

> The exercise covers recognition, the emergency call, the breathing check and
> CPR 30:2 up to handover. **AED use is not part of this exercise:** the
> instructor says to use one, but there is no AED model or AED step.
> `UPSTREAM_README.md` describes the older full scenario with AED and is kept
> only for history.

## What happens in the headset

1. **Start and permissions.** Open *NaReT CPR Witness* and grant camera,
   headset camera and microphone access. Passthrough is on. The patient stays
   hidden until the markers have been seen.
2. **Placement.** Show markers **0, 1 and 2** (DICT_4X4_50, **10 cm** black
   squares, layout in [data/user_marker_layout.cfg](data/user_marker_layout.cfg)).
   The patient's sternum is placed 3 cm headward of the midpoint of markers
   0 and 1. Startup waits until the estimate stops moving, and later updates
   only happen while the viewer holds still.
3. **Fine alignment.** You can nudge the patient with the controllers (left
   stick moves it, right stick turns it and changes its height, **A** saves).
   You can also use hand measurements from the hand menu: a fingertip on the
   floor, a flat hand on the chest or chin, or both hands against the scanned
   torso. A saved alignment is reused in later sessions.
4. **Language and mode.** Choose DE or PL, then *own language* or *neighbour
   language*. Instructions always use the chosen language.
5. **Scenario** (spoken reports, checked against the expected order):
   scene safety → response → ask Anna to call 112 → airway and breathing
   (≤ 10 s, gasping is not normal) → 30 compressions → 2 breaths → repeat
   until handover. The instructor asks yes/no when a report is unclear and
   answers CPR questions from [data/erc_bls_facts.json](data/erc_bls_facts.json).
6. **Compressions** are counted from tracked hands resting on the chest
   (whichever palm is tracked more steadily). Rate and hand position give
   feedback. Hand travel is an **estimate, not measured chest depth**.
7. **Head tilt.** A fingertip held on the chin can tilt the patient's head.
   This only animates the head; it scores nothing.
8. **Debrief.** Handover ends the session and exports actions, counts, timings
   and errors. Ending the session never means the patient recovered.

Hand menu: turn your left palm towards your face. Scenario keys sit above the
fingertips, the state, ECG and 30:2 counter on the palm, and language, mode,
microphone, calibration, export and *Debug* (marker gizmos, hand meshes,
reference scan, depth occlusion) on the forearm cuff.

## Speech and AI

| Part | Where it runs |
|---|---|
| Voice activity, report matching (exact, grammar, fuzzy), baked clips | On the Quest |
| Speech recognition | Uni Greifswald ApphubAI, `large-v3` |
| Unclear reports, Anna's dialogue | ApphubAI LLM, default `unsloth/gemma-4-31B-it-qat-GGUF:UD-Q4_K_XL` |
| Generated voice | ApphubAI `omnivoice`; baked Fish Audio S2 Pro clips for known lines |
| Scenario progression (CCBM) | Native ARM64 filter packaged in the APK |

Cloud replies can steer the dialogue, but they cannot confirm physical actions
or change the patient's state. Without the network, baked instructions and
buttons still work, but there is no live speech recognition. On Android the
app ignores PC loopback overrides, so training needs no laptop. A full session
with no PC attached has not yet been verified end to end. Details:
[docs/API.md](docs/API.md), [docs/QUEST_WITHOUT_PC.md](docs/QUEST_WITHOUT_PC.md),
[docs/LOCAL_SPEECH.md](docs/LOCAL_SPEECH.md).

Credentials come from `.env` (`UNI_API_KEY` or `API_SECRET`, see
`.env.example`) on the desktop, and are written to the headset after install
by `tools/configure_quest.py`. They are never bundled in the APK or the source.

## Setup

```sh
git submodule update --init --recursive   # quest-aruco-avatar is private
python3 tools/setup_dependencies.py --download-vendors
godot --headless --xr-mode off --path . --editor --import --quit
```

On Windows, Godot is not on PATH. Use the console binary of Godot 4.7.2, e.g.
`GODOT=…/Godot_console.exe make test`. The native ArUco and OpenXR vendor
binaries are not checked in. Without them the desktop preview still works,
and it uses a clearly labelled preview pose. Native builds and staging are
covered in [docs/TRACKING.md](docs/TRACKING.md).

## Run, test, record

```sh
make run         # desktop preview with cloud (tools/run_local.py)
make offline     # desktop preview without cloud
make test        # tests/test_*.gd via tests/run_tests.gd
make smoke       # full main scene, DE and PL, offline
make cpr-live    # window: chest compression and recoil
make menu-shot   # render the hand menu without a headset
make erc-video   # scenario 1 on the Meta XR Simulator (silent; audio muxed afterwards)
```

Wrap these commands in `timeout`, because Godot and the recorders can hang.
CI runs only when started by hand (the Actions token cannot clone the private
submodule), so run the checks locally. A run counts as failed if any
`SCRIPT ERROR:`, `Parse Error:` or `ERROR:` line appears in the logs.

## Quest build

```sh
make apk                       # build/naret-quest.apk, signed debug, ARM64 only
python3 tools/audit_apk.py
adb install -r build/naret-quest.apk
python3 tools/configure_quest.py   # --dry-run, --offline, --speech-only
```

Export preset *Meta Quest 3*, package `de.uni_greifswald.naret.cprwitness`.
The APK requests the camera, headset camera, microphone, scene and internet
permissions.

## QCPR manikin

`tools/qcpr_probe.py` logs a QCPR manikin's CPR data over BLE to CSV.
`tools/qcpr_quest_compare.py` and `tools/qcpr_replay_score.py` score the
headset's compression counter against it (latest replay: 60/60 and 31/31
presses, none false). In the app, `scripts/qcpr/` has the CPRM protocol, a
simulated manikin (`F2` on desktop) and a real-BLE backend. The BLE backend
still needs a native Android BLE plugin.

## Where to look

| Path | Contents |
|---|---|
| [scripts/main.gd](scripts/main.gd) | Wiring, dialogue, progression, placement |
| [scripts/tracking/](scripts/tracking/) | Marker fusion, startup placement, motion gate, press counters, touch calibrations, head tilt |
| [scripts/scenario/](scripts/scenario/) | State machine, spoken-report matching, safety report, CCBM bridge, witness director |
| [scripts/ai/](scripts/ai/) | Microphone/VAD, LLM orchestration, observation interpreter, training coach |
| [scenes/main.tscn](scenes/main.tscn) | Patient, Anna and instructor |
| [data/](data/) | Instructor/witness lines, coach steps, ERC facts, marker layout, voices |
| [integrations/ccbm/](integrations/ccbm/) | PDDL model, observation callbacks, native engine wrapper |
| [tools/](tools/) | Setup, voices, recording, QCPR, Quest configuration |

Further docs: [ARCHITECTURE](docs/ARCHITECTURE.md),
[MERGED_APP_FLOW](docs/MERGED_APP_FLOW.md), [BLS](docs/BLS.md),
[DREHBUCH](docs/DREHBUCH.md), [TRACKING](docs/TRACKING.md),
[MODELS](docs/MODELS.md). `AGENTS.md` has the notes for coding agents.

## Limits

Desktop tests and an APK export do not show that the physical setup works.
These still have to be checked on the device:

- the marker layout matches the stickers;
- the patient is aligned with the real manikin;
- camera timing;
- hand counts under occlusion;
- the microphone and the quality of each language;
- frame rate over a full session.

Hand travel is not compression depth, and nothing measures the breaths. The
app does not cover ALS or medication.

## Licence

Own code and procedural assets: MIT (see `LICENSE`). Tracking submodules:
Unlicense. OpenXR Vendors ships its own licence texts. The CCBM runtime is
CC BY-NC-SA 4.0: no commercial use. Fish Audio voices are non-commercial.
Excluded from this repository: API credentials, device calibrations, session
and microphone recordings, model weights, and local build outputs.
