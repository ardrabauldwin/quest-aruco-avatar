# Separate helper and interactive AED — 9 November 2026

This source change enables the general AED scenario in the main app. Anna remains the witness and acknowledges the 112 request. The instructor gives guidance. Marek is a separate scene character (currently the existing male asset, labelled “Marek · AED”), not the instructor.

Ask “Marek, please bring the AED”, “Marek, bring bitte den AED”, or “Marek, przynieś AED”. Other explicit fetch requests can be interpreted by the existing language-model interpreter. Requests go through the rebuilt native CCBM AED model and scenario guards. Accepted device results reach CCBM directly as structural events; announcements are not observations. See `CCBM_AED_INTEGRATION_20261109.md`.

Marek's simulated errand takes the existing 45 seconds. He returns only when a separate standing spot and a separate device footprint can be allocated. A two-second presentation uses the existing male reach clip and the actual right-hand attachment, then the device is set down. There is no unverified walking route through the physical room. Marek generates no compression counts and never attaches pads.

Each character is placed independently using its existing animated-body envelope. A missing spot for one does not hide everyone. The device uses a radius calculated from its actual mesh bounds. Located room geometry is used when available, otherwise the play-area boundary. Boundary-only placement cannot detect unscanned furniture. No room capture or scan popup is introduced. Live geometry is checked again before rendering. The conservative human envelopes can still require more space than the visible body.

In XR the trainee touches the power button, pinches each pad, and releases it near its illustrated chest target. The existing device interaction defaults are unchanged: power touch 2 cm (release 3.5 cm), pad grab 6 cm, pad snap 8 cm. Both pads plus power are required; automatic animated attachment is blocked in XR. Desktop simulation retains its existing shortcut.

Clearance is explicit (“Everyone clear”, “Alle zurück”, “Nikt nie dotyka pacjenta”). Known tracked contact invalidates it and is checked again before analysis or shock. Absence of tracked contact does not prove that everybody is clear; this remains a simulated learner safety check. The device models a fully automatic training AED: analysis delay 5 seconds, a second clearance before shock, then a 3-second countdown. Shock and no-shock paths both return to CPR immediately. Existing 120-second reassessment logic remains. No real shock is delivered.

The core instructor recordings are preserved. New interactive explanations in `data/aed_helper_guidance.json` use the configured runtime speech service and are displayed as text if speech is unavailable; new bundled recordings have not been generated. Existing German/Polish device and Marek recordings are reused. Missing English device lines use runtime speech too. This does not add a PC dependency. Hand-tracking and room placement still need testing on the headset.

No APK, installation, commit, or push is part of this source update.

## Current continuous pattern

The active default is now shock → shock → no shock → repeat, with CPR after every decision. Random recovery and a forced third-shock ending are removed. See `AED_CONTINUOUS_PATTERN.md`.

## Update 13 November 2026 (supersedes the timings and placement above)

- Marek now finishes his sentence, walks about a metre away (kept inside the play area) and only then leaves. The errand is 15 s instead of 45 s (`HELPER_FETCH_S`).
- He walks back in carrying the device, stops 45 cm beyond its place on the head-end side, kneels (patient on the floor) or reaches forward (patient on a table), and the device is lowered from his hand onto its place in 0.7 s. The earlier jump to its place with a 25 cm bounce is removed.
- The device lies beside the patient's shoulder on the trainee's side (0.50 m from the centre line, 0.50 m toward the head), at the height of the surface the patient lies on. Before, it was always at headset-floor height, so with the manikin on a table the device and pads were on the floor.
- Interaction reach: power touch 4 cm (release 6 cm), pad grab within 5 cm of the pad's surface instead of 6 cm from its centre, pad snap 12 cm. `NARET_AED` log lines record power-on, pad taken, pad released (distance to the nearest target) and the delivery spot.
- Marek wears a blue shirt and a beard (texture from `tools/paint_beard.gd`) and uses the instructor's calm listen/talk clips; both still share `human_bystander_male.glb`.
- Not yet checked on the headset: walking in the room, the kneel/reach set-down, and the new pad reach.
