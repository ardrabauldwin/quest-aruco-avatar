# CCBM integration: native runtime and desktop connection tested

Status (2026-10-05): Ubuntu 26.04 installed in WSL2; CCBM generator, filter and
state analyser built. Native tests passed 17 observation prefixes (including
repeated breaths and compression-only mode). A Godot -> HTTP -> native CCBM ->
scenario test passed with supplied transcript strings and simulated test strokes.
This did NOT test the microphone, live hand tracking or the headset connection.
No APK containing this change has been installed. Do not replace the working
headset build until the connection and microphone session pass end-to-end.

Logs: `build/ccbm_linux_setup.log`, `build/ccbm_native_build.log`,
`build/ccbm_native_tests.log`, `build/ccbm_live.log`. The analyser completed with
1,034 states after raising its depth limit to 300. The successful analyser output
was printed during validation; `ccbm_native_build.log` retains the earlier
depth-limit failure. Re-running `build.sh` now uses the corrected limit.
Observed native inference time was approximately 20–30 ms per tested prefix;
this excludes speech recognition and network latency.

Upstream: https://github.com/vac-mmis/CCBMpublic
Inspected source revision: `42672c8946e42447c370c6bf19a655c93965502b`.
The observation callback interface/build command follows `Examples/Shoes`.
Upstream licensing: CC BY-NC-SA 4.0; see its LICENSE for redistribution.

## What changes

Recognised learner speech -> exact grammar or structured meaning extraction -> CCBM observation history ->
real CCBM action posterior -> same-action acceptance >= 0.90 -> existing scenario
precondition checks -> progress. The 0.90 policy and 0.98/0.02 observation
likelihoods are prototype values, not measured recognition accuracy.

The model tracks stage-level events. Hand compression counts and 30:2 cycle
guards remain in Godot. The first accepted compression adds an onset observation;
subsequent strokes do not require a round trip. It does not claim to detect breaths,
responsiveness assessments, or breathing checks from physical sensors.

Only structural event names go to the CCBM worker, not transcripts/audio. The
existing speech-recognition provider still receives microphone recordings.
Anna's LLM dialogue cannot issue clinical transitions. Unknown speech remains
conversation; recognised reports are consumed by the progression adapter.

The default scene now hides routine progression buttons. Placement/calibration,
language, reset and start controls remain; start also has a voice phrase.
Missing worker, timeout, unexpected posterior, stale-session result or unavailable
action never silently advances a step. The app displays an explanatory status.

## Bring up the real engine

1. On this PC, WSL Ubuntu and the generator are installed at `/opt/naret-ccbm`.
   `setup_wsl.sh` reproduces dependency installation and the generator build.
   It normalises Windows line endings and adds the explicit `Control.Monad (when)`
   import required by Ubuntu's newer Haskell libraries. Put `/opt/naret-ccbm` on PATH.
2. Copy this directory to that machine. Run `bash build.sh`.
3. Run `python3 server.py`. It refuses startup without `out/p-filter` and `out/p.states`.
4. Desktop endpoint: `http://127.0.0.1:8766/infer`. For Quest, expose that worker via
   a trusted HTTPS reverse proxy on a restricted network; localhost on Quest is
   the Quest, not the PC. Do not expose this unauthenticated worker publicly.
5. Create Godot `user://ccbm.cfg` on the device:

   ```ini
   [ccbm]
   endpoint="https://YOUR-TRAINING-SERVER/infer"
   ```

   Desktop can alternatively set `NARET_CCBM_URL`. No endpoint is bundled/guessed.
6. Run `python3 test_native.py` for actual engine tests; `test_server.py` exercises
   the parser with fixtures. `tools/check_ccbm_live.gd` exercises the real worker
   from Godot. The parser retains unknown/blocked mass and rejects incomplete output.

## Button-free English sequence after placement/calibration

Speak each phrase separately, waiting for acceptance:

1. "Start exercise."
2. "The scene is safe."
3. "He is not responding."
4. "Anna, please call 112."
5. "He is not breathing normally."
6. Perform compressions; existing hand tracking counts them.
7. After 30, say "I have given one rescue breath" for each completed breath.
   These are labelled spoken reports, not sensor-verified breaths.
   Alternatively say "Use compression only mode" when appropriate for the configured exercise.
8. "Hand over the patient."

German and Polish exact phrases are in `scripts/scenario/spoken_observation.gd`.
Paraphrases now pass through `scripts/ai/observation_interpreter.gd` using the
configured cloud LLM. It requires a whitelisted action/kind/result plus an exact
evidence quote from the input. This schema does not guarantee semantic accuracy.
Questions about findings, plans and compound/uncertain reports prompt clarification;
polite requests such as "Could you call 112?" can be classified as requests.
Opposite findings are preserved and cannot trigger the no-response/no-normal-breathing
path. Stale results are discarded when the stage, session or language changes.
Only fixed phrases remain available if meaning recognition is offline; other
utterances receive clarification instead of an invented action. Speech ASR still
needs online configuration; this is not an offline recogniser.

## Limits and required checks

- Native compilation, sequence output and desktop HTTP wiring passed. Quest
  connectivity, ASR accuracy and live headset performance remain unverified.
- Session histories are capped at 256 codes; only one inference is in flight.
  A report spoken while busy must be repeated. No late/repeated report is queued
  into a later stage. Response timeout is 10 seconds; engine timeout is 8 seconds.
- The worker replays a short sequence per request; benchmark before relying on
  it live. It is a prototype, not a persistent high-throughput filter service.
- CCBM cannot establish that a physically unobserved act actually occurred.
- Scenario stage guards still own acceptance order and compression-cycle counts.
- Test normal EN/DE/PL sessions, out-of-order statements, negation, network loss,
  reset during inference, and failed speech recognition before headset deployment.
