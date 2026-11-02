# Bystander placement in small rooms

Status 2026-10-29. Changes `scripts/tracking/room_layout.gd` and `scripts/main.gd`
(`_place_bystanders`). Headless tests in `tests/test_tracking.gd`
(`_test_scored_spots`). Not yet seen on a headset.

## Problem

Anna and the instructor stand on scanned free floor. The strict search
(`pick_spots`) rejected any point closer than 0.45 m to a wall, 0.35 m to
furniture or 0.9 m to the other speaker, outside a 1.2–2.6 m ring around the
patient, or inside a 1.1 x 2.2 m trainee zone. Together that needed roughly
3 x 3.5 m of clear floor. In a smaller or cluttered scanned room both speakers
were hidden, while an unscanned room kept the patient-relative fallback.

## Changes

1. **Smaller distances.** Wall clearance 0.30 m, furniture clearance 0.25 m,
   separation 0.6 m, an extra 0.9 m ring, and the trainee zone shrunk to
   0.7 x 1.5 m beside the chest. The strict search now succeeds in a 2.2 m
   square room beside the patient.
2. **Scored fallback.** When the strict search finds fewer than two spots,
   `score_spots` chooses the best floor instead of none. Hard rules stay hard:
   on the scanned floor, never inside the patient, trainee or furniture
   rectangles, and at least 0.25 m (half a shoulder width) from any of them, so
   nobody stands half inside a wall. Within that, wall clearance and the
   distance to the patient become a score:
   `min(clearance, 0.6) - 0.5 * |distance - 1.5|`, minus a penalty for crowding
   the other speaker (never closer than 0.4 m).
3. **Still hidden when there is no room.** Below 0.25 m of clearance the floor is
   unusable and the speaker stays hidden, as before. Kneeling as a way to use
   narrower spots was tried and dropped (2026-10-29): the only kneel clip is
   the start of the CPR take and the turn logic plays walk steps.

## Limits

- Scoring cannot create space: a speaker may stand with shoulders near a wall
  in a cramped room. It never stands inside scanned furniture or on the patient.
- Objects the room scan does not know about (moved chairs, unlabelled items)
  are invisible to both searches, as before.
- The scored path is exercised by geometry tests only; room-scan behaviour on
  the Quest still needs a check with `NARET_ROOM scored_fallback` in the log.
