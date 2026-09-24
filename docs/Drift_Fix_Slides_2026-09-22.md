# Avatar drift: cause, fix, verification

## Slide 1 — Why the avatar drifted, and how the cause was found

- Observation: the avatar sat correctly from the front, slid sideways from the sides, and moved away from the viewer at distance.
- Assumption used: the mannequin does not move during a recording, so one marker must land on one spot in the room from every viewpoint.
- Data: 7 recorded walks around the mannequin, 3 and 9 September 2026, 3 markers each, giving 21 independent fits.
- Method: for each view, marker position in room = head position + s × (marker offset from camera). Unknowns: the true spot X and one scale s. Least squares over all views; X drops out as the mean, s has a closed form. No external reference value is needed.
- Result: s = 0.937 in every session (common marker 0.932 to 0.940; all 21 fits average 0.937). The detector measured every distance about 6.7 percent too long.
- Signature: the error lay along the line of sight, lateral error about 1 cm. That points to range, not to lens distortion or the principal point.
- Fix: camera focal length scaled by 0.937 (877.1 → 821.8, 878.3 → 823.0). Applies to all markers equally; independent of marker placement.
- Verification: after the fix, two new recordings (15 September) fit s = 1.000, 0.990, 1.005. Side-view error dropped from 6 to 12 cm to about 3 cm.

## Slide 2 — What remained and what was done about it

- Residual: beyond 1.2 m the range still read too long, by 6.4 percent of the extra distance (both markers, both sessions agree). Corrected per marker before placement; common and navel then within 1 cm out to 2.2 m.
- Mirror poses: from the side the detector sometimes returns the flipped solution of a flat marker, 30 to 40 degrees turned and 12 to 14 cm off (33 % of left-view samples for the common marker, 86 % of right-view samples for the chest). Rejected by a face-direction test at 45 degrees; the marker's last good pose stands in for up to 1 second. This removed the turning and the jumps.
- Re-anchor thresholds raised to 8 cm and 8 degrees so viewpoint bias is not mistaken for the mannequin being moved.
- Open: focal length and headset tracking scale are indistinguishable from these data; a tripod tape test would decide. Beyond 2 m the chest marker keeps a steeper error not covered by the model. Next accuracy step is one pose from all 12 marker corners in the detector, which needs a change in the C++ side.
- Not the app: the headset has been tracking in low-light mode, relocalising about once a minute; the per-frame trace shows the avatar steady to under 0.5 mm while the user saw shaking.

## Slide 3 — Why the mirror-pose test is needed even though the floor lock discards tilt

- The question: the floor lock already forces the avatar flat, so why not floor-lock first and skip the mirror test?
- What the floor lock does: reads one thing from the marker, its along-body axis, flattens it onto the floor and keeps that as the heading; overwrites the face direction with the room's down; copies the position through untouched. It never inspects the sample, so it cannot reject one.
- What a mirrored sample is wrong about, three things at once: face pointing sideways (85 to 95 degrees from up instead of 5 to 25), heading turned 30 to 40 degrees on the floor, position shifted 12 to 14 cm. From the side the picture fits both candidates, so the detector's pick is a coin toss.
- A mirrored sample through the floor lock: turned heading flattened and taken as truth; shifted position copied through; sideways face overwritten and gone. Output: a clean, flat, confident, wrong pose. Fused with the good ones, the avatar's feet swing about 60 cm for a 35 degree turn, pivoting about the chest marker.
- A mirrored sample through the test: the test reads the face direction, the one thing the floor lock throws away. Sideways means the whole sample is dropped, wrong heading and wrong position with it; the marker's last good pose stands in for up to 1 s. Only surviving samples are fused and then floor-locked.
- Floor lock earlier: every sample would reach the test already flattened, face direction equal to down, angle 0. The test would pass everything, including the mirrors. Same as having no test.
- Rule: the face direction must be read before it is discarded. The order is not the point; the check could live inside the floor lock, but it would be the same test.
- Two different angles: the 45 degree threshold is on tilt (face against up); the 30 to 40 degrees is the heading error that leaves with the rejected sample and is never measured at run time.
- Removing the mirror at the source (choose the candidate facing up, or hold each marker's known tilt fixed in the solve) needs the marker corners, which only the C++ detector has.

## Slide 4 — Re-anchor threshold 8 cm / 8 degrees: why it is tied to the viewpoint error, and how it was set

- What re-anchor watches for: the filter holds a rest pose and re-anchors when the incoming measurement settles at a new spot and stays there, steady, over several detections. That pattern is its definition of "the mannequin was moved".
- Why the viewpoint error matters: the filter never sees the mannequin, only the detector's numbers. Walk to the side and stop: the markers read about 5 cm off, steadily, for as long as you stand there. A stable measurement somewhere else, exactly the pattern above. A real move and a viewpoint error are indistinguishable to it.
- So the threshold is a size test: it must sit above the largest false alarm the test can receive, and the viewpoint error is that false alarm. Below it, walking round the mannequin re-anchors it. On the headset on 15 September, with floors of 4 cm and 3 degrees, the avatar crept toward the far viewer and turned a few degrees "at times", and jumped back on returning to the front.
- How 8 / 8 was set: bracketed, not fitted. Lower bound: residual viewpoint bias after the focal-length fix, about 4 to 6 cm and a few degrees (15 September recordings). Upper bound: real moves in the recorded tests, 105 to 300 mm and tens of degrees. 8 cm / 8 degrees is about 1.5 to 2 times the bias and well under the smallest real move. No data separates 8 from 7 or 10.
- What it costs: a real move under 8 cm / 8 degrees is not followed. The avatar stays put, off by that amount, until the mannequin moves further or is re-placed by nudge.
- How to lower it: give the filter the cause, not just the size. The marker error changes only while the head moves; the mannequin can move at any time. Viewer-motion gate (built 16 September, replay OK, reverted with the CPR rollback): hold while the head moves; once still for 0.5 s, average 5 readings; up to 6 cm / 6 degrees is bias and is subtracted, more is a move and is followed; over 15 cm / 15 degrees on 3 detections is followed at once; no small-move verdict beyond 1.8 m. The floor could then drop to 3 to 4 cm.
- Not a fix: enlarging the avatar to hide a few centimetres. The CPR hand target on the chest needs centimetre placement, and +5 percent already looked too wide on video.
- Note: the range correction has since cut the far-view bias to about 3 to 4 cm, so the floor could come down a little even without the gate; no evidence yet that it needs to.

## Sessions used for the fit

| Recorded | Session | Common | Chest | Navel |
|---|---|---|---|---|
| 3 Sep 11:57 | stationary_1788429422 | 0.935 | 0.916 | 0.930 |
| 3 Sep 12:08 | stationary_1788430085 | 0.932 | 0.892 | 0.920 |
| 3 Sep 12:14 | stationary_1788430472 | 0.935 | 0.917 | 0.932 |
| 9 Sep 13:58 | viewpoint_1788955119 | 0.939 | 0.930 | 0.949 |
| 9 Sep 15:24 | viewpoint_1788960247 | 0.937 | 0.943 | 0.971 |
| 9 Sep 15:26 | viewpoint_1788960379 | 0.934 | 0.932 | 0.955 |
| 9 Sep 17:17 | viewpoint_1788967039 | 0.940 | 0.932 | 0.926 |

Script: `tools/depth_scale_fit.py <recording.csv>`.
