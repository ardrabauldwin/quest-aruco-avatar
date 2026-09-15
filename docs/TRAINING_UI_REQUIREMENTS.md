# Training display requirements

Recorded from the user's instructions on 2026-09-08. Implemented in `project/cpr_feedback_hud.gd` on 2026-09-14: two side-by-side panels: LEFT a speed half-dial (60-160 per minute, green 100-120, needle + number, `--` below two measured intervals); RIGHT the phase title (PLACE HANDS / PRESS WITH THE BEEP / COMPRESS / GIVE 2 BREATHS), the count out of 30, one instruction per press (Press deeper / Too deep, ease off / Good depth, press faster|slower / Good press / Keep your hands in view; depth outranks pace) and a depth bar (0-8 cm, green 5-6 cm, marker = last completed press, `--` while tracking is unreliable); the 30:2 pause reads '30 compressions done - give 2 breaths'. Feedback is visual only by decision (2026-09-14): the metronome beep stays the single sound so the rhythm is never masked. Tests: `project/tests/test_cpr_feedback_hud.gd`. The placement ring/text at the chest is unchanged.

## Hand placement

- Replace the placement symbol/ring with the text **Place hands here**.
- Display the text in green at the chest hand-placement target.
- Green is an instruction colour, not proof that placement was detected correctly.

## Speedometer

- Show measured pressing speed in BPM, separately from the metronome's target BPM.
- Show the target band in green and the ranges below and above it in red.
- Proposed adult training band: 100-120 BPM, following the guidance discussed in this conversation.
- Use a needle/marker and a numerical BPM reading.
- Estimate cadence across several detected repetitions; show an unavailable state until sufficient reliable motion is present.

## Depth bar

- Add a separate depth bar with a numerical reading in centimetres.
- Show the target band in green and values below and above it in red.
- Proposed adult training band: 5-6 cm, following the guidance discussed in this conversation.
- Label the current measurement **Estimated hand travel**; Quest hand motion has not been validated as actual chest compression depth or recoil.
- Show the latest repetition's peak excursion separately from live travel so normal release does not falsely indicate a shallow completed press.
- Use an unavailable state during unreliable tracking; do not present missing data as a successful measurement.

## Existing requirements retained

- Slow presses and pauses must not reset accumulated counts.
- Pace feedback and metronome phase must not reject an otherwise detected repetition.
- Keep the speed and depth displays distinct from the repetition counter.

## Reliability work identified by review

- The strict 5 cm counting threshold misses simulated boundary cases at 72/90 Hz.
- A single-frame position spike can create a false count.
- A tracking interruption discards an unfinished repetition.
- These issues must be addressed and tested before presenting the display as reliable training assessment.
- Headset audio and real hand tracking still need on-device verification.
