# Upper-palm motion selection

Implemented in `project/cpr_hand_zone.gd` on 2026-09-08.

At acquisition, the app prefers the upper palm when both have valid, actively tracked positions inside the motion target region. It compares positions along the chest's outward normal. If only one palm is usable, it can start tracking that palm without requiring the other to become visible. Its stack order is then unknown. Position order is not proof of chest contact or correct stacking.

Once selected, the hand remains selected while usable. If it is lost or leaves the target region, the app automatically switches to the other usable palm. Every switch discards the unfinished stroke and establishes a fresh position baseline, while preserving completed counts and cycle progress. This avoids counting the gap between palms as movement. No manual reset is needed. The app stays with the fallback while usable, even if the original hand returns. If both hands disappear, it preserves counts and resumes automatically when a usable palm returns. The incomplete press at a switch may be missed; continuous correct counting across an unobserved movement cannot be guaranteed.

Estimated travel is the selected palm's starting height minus its lowest height along the chest normal, corrected for XR world scale. The fixed separation between palms is not added to travel. This remains an estimate of hand movement, not validated chest compression depth.

Tests use synthetic XR joints with both hand orders, 25/55 mm spacing, a rotated and scaled mannequin, XR world scales of 1.0/1.5, and upper-palm tracking interruptions. They verify upper preference, single-palm acquisition, 55 mm travel, automatic fallback in both directions, zero travel at a switch, count preservation and continued counting without a manual reset.

The position-spike false counts and the return-to-original-top lock-up found in `audit_cpr_motion_edges.gd` were fixed on 2026-09-14 (`cpr_motion_session.gd`: a press must spend at least 40 ms below the top, and a press that recoils most of the way and then starts the next press from a lower resting height completes with that recoil peak as the new top). A dropped tracking frame still discards the current stroke; that rule is unchanged. This change implements upper-palm selection only; the speedometer and depth-bar UI requirements are recorded in `TRAINING_UI_REQUIREMENTS.md` and are not implemented yet.
