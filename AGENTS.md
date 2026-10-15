# AGENTS.md

Notes for coding agents (Claude Code, Codex, …) working on NaReT Mannequin-XR: a
Godot 4.7 OpenXR app for Quest 3 that trains adult BLS with AED (ERC 2025) in
German and Polish, overlaid on a physical CPR mannequin. User docs: README.md,
architecture: docs/ARCHITECTURE.md, scenario script: docs/DREHBUCH.md.

## Commands

Wrap every command in `timeout`; Godot, the simulator and the recorders can hang.

```sh
timeout 300 godot --headless --xr-mode off --path . --editor --import --quit
timeout 300 godot --headless --xr-mode off --path . --script tests/run_tests.gd   # make test
timeout 120 env NARET_OFFLINE=1 godot --headless --xr-mode off --path . -- --smoke-test
timeout 120 godot --headless --xr-mode off --path . --check-only --script <file.gd>
timeout 1200 tools/record_xr_scenario.sh   # make erc-video: scenario 1 on the Meta XR Simulator
```

GitHub CI is manual-only (workflow_dispatch) for now: the Actions token cannot
clone the private submodule `third_party/quest-aruco-avatar`. Run the checks
locally. When it runs, it fails on any `SCRIPT ERROR:`, `Parse Error:` or `^ERROR:` line in import,
test or smoke logs, not only on failing checks. Keep those logs clean.

## Rules

- **ERC 2025 order** (docs/BLS.md): unresponsive → 112 on speaker right away →
  airway + breathing ≤ 10 s (agonal = not normal) → AED → CPR 30:2,
  100–120/min, 5–6 cm. With two rescuers CPR continues while the pads go on.
  Tests and tools must submit actions in this order (`call_emergency` before
  `check_breathing`).
- **Silent recordings:** anything that plays TTS on this machine runs with
  `--audio-driver Dummy`; audio is muxed from the clip files afterwards.
- **No secrets in output:** API keys come from `.env` / the OmniRoute store;
  never print them.
- **Voices** are baked with `tools/generate_voices_fish.py` (Fish Audio S2 Pro,
  non-commercial licence) from `data/instructor_lines.json` and
  `data/bystander_lines.json`; check with `tools/check_voices.py`.
- **Tests** are `tests/test_*.gd`, extending `res://tests/suite.gd` (`check()`).
- Don't edit a shell script while it runs; don't commit without being asked.

## Placing the patient on the mannequin (sternum marker)

Mannequin-agnostic: one ArUco marker (DICT_4X4_50, default id 0, 5 cm) lies
flat on the compression point of the sternum and stays there during CPR.

- Marker +Y = chest normal, marker −Z = toward the head. Uncalibrated,
  `NaretSpatialAnchor.sternum_offset()` puts the patient's `sternum` node under
  the marker (plus `marker_thickness_m`). A saved calibration overrides it.
- The anchor follows the marker only until the pose has rested for 1.5 s,
  then holds it (`locked`). Compressions (the marker sinks 5–6 cm) and hands
  covering it change nothing; a new resting pose > 1.5 cm / 5° away re-places
  the patient (mannequin moved). The chest shows depth via
  `set_compression_depth`, never by moving the anchor.
- Desktop/simulator preview poses are marker poses: `patient spot *
  marker_to_mannequin⁻¹`.
- Details and limits: docs/TRACKING.md, "Marker auf dem Brustbein".

## Video review

`~/.claude/skills/gemini-video-review` (Gemini via local OmniRoute) reviews a
recording section by section; `build/loop_round.sh` runs record → review.
Verify its findings against the app's logs before fixing.
