# CCBM AED integration and announcement fix — 9 November 2026

Both the full scenario and the actual upstream CCBM filter now include the AED sequence. No LLM-generated speech or played announcement is used as proof that a shock occurred.

## Event path

- Accepted app events append structural observation codes to CCBM history.
- Pad attachment, analysis, the scripted shock/no-shock result, actual simulated shock completion, no-shock CPR return, reassessment and first resumed compression are represented in the PDDL/native observation model.
- Clearance uses two distinct model actions (before analysis and before shock), mapped to the shared `clear_patient` observation. A rejected tracked-contact event still revokes the model's clearance. Repeated contact polls do not fill the history.
- Spoken AED requests and clearance confirmations now pass through native CCBM inference and the existing scenario guards. Speech cannot inject pad attachment, analysis outcomes or shock-completion events.
- On Android, accepted AED events trigger background native tracking updates (`NARET_CCBM_TRACK`). Those posterior updates do not execute another shock or compression. Ordinary individual presses are counted locally; only a new compression onset is sent after an AED pause.
- History changes and contact during pending inference invalidate stale speech decisions. Reset clears the native observation history and tracked posterior.

## Model/runtime changes

The PDDL, observation callbacks, host protocol, native adapter, state table, Android ARM64 executable/AAR and model manifest were rebuilt together using pinned upstream revision `42672c8946e42447c370c6bf19a655c93965502b`.

The upstream default forbids revisiting symbolic states. That made a second CPR return impossible when it reached the same state as a previous cycle. Both host and Android now use `-v 1`: neutral revisiting, which permits repetition without rewarding it.

Accepted software events use exact symbolic emissions. This means the simulator emitted that event, not that the real patient was clinically assessed or the learner's technique verified. Spoken request/report likelihoods remain prototype values (0.98 matched, remaining 0.02 distributed across other speech codes); these are not learned accuracy estimates. The existing 0.90 speech acceptance threshold was not lowered. Old witness-only model manifests are refused explicitly.

## Announcements and counting

The AED queues “No shock advised” before automation consumes that result and returns to CPR. The announcement cannot disappear merely because the state has already advanced. CPR does not wait for the audio. The existing “Shock delivered” announcement remains tied to the simulated shock event.

Both shock and no-shock return start a fresh compression set at zero; the next accepted press is one. The session total remains saved. The instructor explains this in English, German and Polish. New explanatory speech still uses the configured speech service, with displayed text; new offline recordings have not been generated.

## Verification

- 120 prefixes run through the actual compiled upstream host filter: repeated shock/no-shock cycles, early AED request, contact interruptions, initial nonshockable case, compression-only mode, scripted recovery, and legacy witness mode.
- Six host protocol unit tests.
- Android ELF architecture and executable hash, model domain hash and decoded state-table hash checked against the packaged manifest.
- Full Godot regression suite and smoke check; results are recorded in `build/ccbm-aed-godot.log`.

The ARM64 artifact was cross-compiled, not executed on Quest in this session. No APK was built or installed, and nothing was committed or pushed.
