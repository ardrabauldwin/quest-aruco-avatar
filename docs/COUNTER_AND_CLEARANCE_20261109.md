# Missed compressions, AED clearance loop, AED preview — 9 November 2026

Build `0.3.20261109-counter-clearance` (`build/NaReT_Quest_Counter_Clearance_20261109.apk`).

## 1. Missed compression counts

The counting code in the headset build of 14:40 was byte-identical to Friday's build
(`naret-quest-face.apk`, 6 Nov); only `main.gd` differed. The headset traces
(`user://cpr_trace_*.csv`) explain the difference:

| Session | Palm the counter followed | Counted / strokes seen in the other palm |
|---|---|---|
| 6 Nov 18:03 | left, the only palm in the zone | 30 / 30 |
| 9 Nov 13:54 | right, lower palm of the stack | 11 / about 16 |
| 9 Nov 14:49, first 33 s | right, lower palm of the stack | 7 / about 25 |
| 9 Nov 14:49, after 46 s | left, after the right palm left the zone | 22 / 22 |

The Quest damps the motion of the occluded lower palm to 1–3 cm per stroke, below the
2 cm press start. The lower palm settled first, the first press locked setup, and the
upper palm could never acquire a saved rest, so the counter stayed on the lower palm.

Fix in `scripts/tracking/two_hand_press_counter.gd`: a palm without a saved rest may
still collect one after the lock, but only while the chest is up (no press in progress,
every calibrated palm within 1 cm of its own rest). The existing rule "prefer the higher
saved rest between strokes" then moves counting to the upper palm. A palm lying still on a
depressed chest still gets no late rest (`tests/test_upper_hand_after_lock.gd`,
`tests/test_fixed_hand_rest.gd`).

Replay of the three traces through the fixed counter (`tools/replay_cpr_trace.gd`):
6 Nov 30 → 30, 13:54 11 → 24, 14:49 30 → 57.

```sh
godot --headless --xr-mode off --path . --script tools/replay_cpr_trace.gd -- --trace <cpr_trace.csv>
```

## 2. Instructor repeats "stand clear", shock advice never comes

`xr_interaction.gd` polled a contact envelope of ±34 cm around the body axis, up to 44 cm
above the back, every 0.15 s during the AED phase. A learner kneeling beside the manikin
or working the AED next to the shoulder was inside it, so `patient_contact` revoked each
clearance before the 5 s analysis finished; the speech diagnostics of 14:49 show
`aed_clear → ccbm_accepted → aed_analyse → aed_clear` repeating.

Fix: the envelope is a 10 cm band each side of the patient's centre line (requested
width; shoulders and arms lie outside it), back −4 cm to chest +7 cm (the body frame
origin sits 20.7 cm below the sternum), and contact must be seen on two consecutive
polls (0.3 s) before clearance is revoked (`tests/test_contact_envelope.gd`). Absence of
tracked contact still proves nothing; clearance is still spoken and scored by CCBM.

## 4. Anna, Marek and the AED floating above the floor

Build `0.3.20261109-patient-floor`. The speakers and the AED home spot used the headset's
floor reference (`anchor.floor_y`, the OpenXR floor-based space). In the 9 Nov sessions the
marker-measured sternum sat 10.5, 13.8 and 41 cm above that reference, i.e. the reference
was 7 to 30 cm away from the surface the manikin lies on, so the characters stood in the
air and Marek set the AED down in the air.

Decision (9 Nov 2026, after trying a manikin-based floor): the speakers and the AED
stand on the floor the headset reports, never on the patient's height. The trainings
happen in different rooms, and a mannequin on a bed must not lift the characters. The
fingertip floor correction (hand-menu key "Boden", `floor_touch_offset_m`) remains the
way to fix a wrong headset floor (`tests/test_speaker_floor_from_patient.gd`). One log
line per placement, `NARET_FLOOR_CHECK`, records the headset floor, the marker-placed
sternum and the wearer's head height for later checks. In the 9 Nov sessions the
headset floor sat about 8 cm above the manikin's underside; the characters stood
visibly right only when lowered by that amount.

Root cause of the wrong headset floor: `project.godot` requested the OpenXR *Local
Floor* space (`xr/openxr/reference_space=2`). On the Quest the runtime reported a sitting
play area at start-up and the floor-level space appeared only afterwards; Godot can
emulate Local Floor from that start-up state, and the result differed from the boundary
floor by 7–9 cm (once 21 cm). The app now requests the *Stage* space (`=1`), the boundary
floor itself, locks the floor only once a floor-based play area is reported, and re-reads
it on `pose_recentered` / `reference_frame_changed` (`_on_floor_space_changed`), so the
characters and the AED spot follow the boundary floor. `NARET_XR_SPACE` and
`NARET_FLOOR_CHECK` log lines show the space in use and the floor/underside/head heights
per placement.

Also removed: `_place_bystanders()` forced the AED model visible every second while
`aed.sync()` hid it again, which made the device flicker at its spot from the first
scene on.

## 6. Fingertip floor correction guarded

Session of 9 Nov 17:4x: the hand-menu key "Boden" accepted a fingertip resting on the
manikin or a knee as the floor, 64 cm above the stage floor, and saved it
(`floor_touch_offset_m=0.641`); Anna, Marek and the AED then stood 64 cm in the air.
Decision: the Quest boundary floor, set per room in the headset's boundary setup, is the
default and the characters always stand on it; the fingertip touch stays as the manual
correction. `_floor_touch_plausible()`: within 30 cm of the headset floor any touch is
accepted; a larger correction (stale Space Setup, 0.9 m on 2026-10-29) only when the head
is at least 1.2 m above the touch. A rejected touch says how far from the headset floor it
was. A saved correction beyond 30 cm that the running session did not verify is dropped
at start (`tests/test_floor_touch_plausible.gd`, `tests/test_stable_floor_reference.gd`).

## 5. Characters inside the headset boundary

The default (patient-relative) spots ignored the boundary; the strict solver that used it
needed circles the size of a character's arm reach plus 30 cm wall clearance and failed
in small rooms. `main.gd` `_fit_default_spots_to_boundary()` now pulls Anna, the
instructor, Marek and the AED spot inside the play-area outline
(`SpeakerPlacement.inside_outline`): 5 cm from the boundary, 30 cm off the patient,
60 cm apart where the room allows, in that priority. A roomy boundary, or none, leaves the
free spots unchanged (`tests/test_default_spots_inside_boundary.gd`). The free spots
moved closer the same day: 1.0 m in front of the patient (was 1.2), Anna and the
instructor 0.6 m to each side (was 0.8), Marek 0.6 m behind their gap (was 0.9).

## 7. Quest hand-tracking depth versus the QCPR manikin

`tools/compare_qcpr_trace.py` lines the headset's presses (cpr_trace `unix_ms`/`count`/
`travel_m`, or a logcat with epoch timestamps) up with `tools/qcpr_probe.py` compressions
(`pc_unix_ms`, new column) and prints depth per matched stroke, the clock offset it found
and a summary. The 3 November 2026 recordings in Downloads:

| Recording | matched | manikin depth | Quest depth | Quest − manikin | ratio |
|---|---|---|---|---|---|
| 11:46 | 33 of 35 | 28–31 mm (steady phase) | 50–60 mm | +25 mm mean, sd 15 | 1.8 |
| 12:11 | 4 of 7 | 42–45 mm | 48–66 mm | +16 mm mean | 1.4 |

The Quest measures palm travel, not chest travel: the heel of the hand sinks into the
manikin's chest cover, the wrist flexes and the tracked palm joint overshoots at the
bottom of the stroke. Depth from hand tracking therefore reads about 2 cm deeper than the
manikin. Rate and count match where the Quest sees the strokes; in the 11:46 recording 7
Quest presses had no manikin compression and 2 manikin compressions were missed.

Live comparison the same evening (`build/depth_comparison/qcpr_20261109_1924_continuous_*`,
10 continuous strokes of 22–25 mm, probe from commit 9210cda): the counter's travel from the
saved rest reported 10–12 cm because the rest was saved while the hands hovered up to 8 cm
above the chest. Three estimators per stroke against the manikin:

| Estimator | Error, 10 strokes |
|---|---|
| top (counting) palm travel within the stroke × 0.45 | +0.1 cm mean, sd 0.5 cm |
| 1.5 cm minus the lowest point of the hidden lower palm | +2.6 cm mean, sd 6.3 cm (one 23 cm glitch) |
| fixed stack height minus the top palm's lowest point | +4.2 cm bias |

A second set of 30 continuous strokes (`qcpr_20261109_1930_deep_*`, the wearer pressing as
deep as possible: manikin 22–34 mm, rate 63–84/min) gave palm travel 5–9.6 cm for chest
travel 2.2–3.4 cm (ratio 2.9). Pooled over 40 strokes the manikin depth hardly follows
the palm travel (correlation 0.37; linear fit depth ≈ 0.07 × travel + 2.0 cm): the hands
move far more than the chest, and differently from stroke to stroke. A fixed factor is
therefore a population average: × 0.40 gives +0.3 cm mean error, 0.5 cm spread over the
40 strokes, but no per-stroke sensitivity. `cpr_hand_zone.gd` reports chest depth =
counting-palm travel within the stroke × `TOP_PALM_DEPTH_FACTOR` (0.40), labelled an
estimate (`tests/test_chest_depth_from_surface.gd`). Count and timing matched the
manikin 10/10 and 30/30. Reliable depth needs the manikin's sensor in the app; the app's
Bluetooth backend is a stub without a native plugin (see the decision in the chat of
9 Nov: native Quest plugin or laptop bridge).

Ruler check (`NaretXRInteraction.ruler_measured`, build `0.3.20261109-ruler`): pinch
both hands on the two ends of a tape measure and the app shows the distance between the
index fingertips and their heights above the floor, log line `NARET_RULER`. If a 30 cm
ruler reads 30 cm, hand tracking is metrically right and the depth error is the
hand-on-chest mechanics above, not the tracking scale.

## 3. AED visible from the first scene

`main.gd` showed the default-spot AED preview on the headset once the patient was
placed. The preview is now desktop/simulator only; on the Quest the device appears when
Marek brings it (`tests/test_default_character_stage.gd`).
