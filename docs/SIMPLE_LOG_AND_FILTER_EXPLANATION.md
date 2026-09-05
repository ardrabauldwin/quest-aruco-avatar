# Simple explanation of the ArUco log and pose filter

## 1. The question

The avatar has to be placed on one point of the body. Call that point the
**common point**. A marker sitting exactly on it would answer the question
directly, but that marker cannot stay there during normal use.

So the common point has to be **reconstructed** from two markers that can stay
on the body. The whole analysis answers one question:

> How much accuracy do we lose by reconstructing the common point instead of
> measuring it directly?

## 2. The markers

| Marker | Role |
|---|---|
| ID0 | the common point; used only as the reference during testing |
| ID1 | chest marker; permanent |
| ID2 | torso marker; permanent |

The CSV header calls ID2 `navel`. Only the name is old. The recorded ID2 data
is correct.

## 3. How the log was recorded

The Quest runs OpenCV on each camera image and produces a dictionary of
detected marker poses. The logger copies that dictionary and writes one CSV row
per **new** OpenCV result — not one row per Godot render frame, which would
write the same result many times over.

Each row holds:

- the time;
- the Quest camera pose at capture time;
- for each visible marker, its position `(x, y, z)` and rotation quaternion
  `(qx, qy, qz, qw)`.

Marker poses are stored **relative to the camera**. The camera pose in the same
row converts them to world space.

This is pose data, not a video recording.

## 4. The one idea: a fixed offset

The three markers are stuck to the same rigid body, so the step from any marker
to the common point never changes. That step is the **offset**:

```text
chest_to_common = inverse(ID1 chest) * ID0 common
torso_to_common = inverse(ID2 torso) * ID0 common
```

Once an offset is known, ID0 is no longer needed:

```text
estimate from chest = ID1 chest * chest_to_common
estimate from torso = ID2 torso * torso_to_common
```

When both estimates exist, they are averaged into one fused pose.

## 5. The rule that makes the test honest

An offset is **learned** from the first 30 complete samples (about three
seconds). It is **scored** only on the samples that come after.

This matters. If an offset is scored on the same frames it was fitted to, the
fit has already absorbed the noise in those frames, and the reconstruction looks
steadier than the ID0 it is reconstructing — which is impossible in a real run.
All three experiments use the same split, so their numbers can be compared.

Every error below is the distance between two poses **from the same row**:
the estimate, and directly detected ID0. Comparing within one row cancels the
real movement and the camera pose, so what is left is reconstruction error
alone.

## 6. Experiment 1 — everything stationary

Nothing moves. This measures ordinary tracking wobble around the resting
position.

| Common-pose source | Median | p95 | Worst |
|---|---:|---:|---:|
| Direct ID0 | 0.77 mm / 0.23° | 3.51 mm / 0.52° | 10.9 mm / 2.8° |
| From ID1 chest | 0.94 mm / 0.34° | 4.26 mm / 0.85° | 10.6 mm / 2.5° |
| From ID2 torso | 1.05 mm / 0.39° | 2.41 mm / 0.80° | 35.0 mm / 13.0° |
| Fused ID1 + ID2 | 0.88 mm / 0.26° | 3.47 mm / 0.57° | 14.4 mm / 7.7° |

`p95` means 95 percent of samples were better than this value.

Two things stand out:

- **Typical error is under a millimetre.** Reconstruction costs almost nothing
  in the normal case: fused is 0.88 mm against ID0's own 0.77 mm.
- **The worst case is much worse than the typical case.** ID2 is the steadiest
  marker most of the time (best p95) yet produces the single worst sample,
  35 mm and 13°. Rare bad detections, not everyday wobble, are the real problem.

The largest errors appear at samples 257–259 in **both** the fused estimate and
direct ID0. Because both fail together, the disturbance came from the scene or
the ID0 detection itself, not from the reconstruction.

## 7. Experiment 2 — markers moving

The markers are moved after the calibration samples. Two recordings were made
and both are reported here.

| Recording | From ID1 chest (p95) | From ID2 torso (p95) | Fused (p95) |
|---|---:|---:|---:|
| `1785327929` | 9.59 mm / 3.34° | 10.76 mm / 6.80° | 8.48 mm / 4.55° |
| `1785327343` | 14.63 mm / 4.54° | 17.60 mm / 6.74° | 15.84 mm / 5.02° |

Medians were 4.13 / 6.19 / **2.96 mm** and 5.60 / 6.64 / **6.14 mm**.

Error during movement is roughly **three times** the stationary error.

Note what does *not* explain this. All three markers are detected in the same
camera image, so capture latency shifts them equally and cancels out in a
same-row comparison. What is left is the image itself: motion blur softens the
marker corners, and a moving marker is seen from changing angles, which is
exactly when a flat marker's rotation is hardest to pin down. The rotation
error grows more than the position error, which fits that explanation.

Fusion is not reliably the winner here. It was best in `1785327929` but ID1
alone beat it on position in `1785327343`. The honest conclusion is that fusion
helps rotation and is roughly neutral for position under movement.

## 8. Experiment 3 — hiding a marker

ID0 stays visible as the reference. ID1 and ID2 are covered in turn, to test
what happens when only one permanent marker is left.

| Condition | Samples | Median | p95 |
|---|---:|---:|---:|
| Both visible, fused | 119 | 2.80 mm / 0.95° | 6.17 mm / 1.83° |
| ID1 hidden, use ID2 | 66 | 2.31 mm / 1.92° | 9.39 mm / 4.31° |
| ID2 hidden, use ID1 | 62 | 5.58 mm / 1.12° | 9.86 mm / 1.74° |

This is the section that decides the design:

- **Either marker alone is enough to keep the avatar placed.** Losing one costs
  roughly 3 mm at p95 — a degradation, not a failure.
- **The two markers are good at different things.** ID2 gives the better
  position (2.31 mm median), ID1 gives the clearly better rotation (1.74° p95
  against 4.31°). Neither dominates, which is why both are kept.
- **Fusion is best when both are visible**, better than either alone on both
  position and rotation.

## 9. From measurements to filter settings

The measurements lead to three separate decisions.

**Rare bad detections → take a medoid.**
Section 6 showed the danger is not everyday wobble but the occasional 35 mm
detection. Smoothing cannot help with those: it averages a bad pose in instead
of rejecting it. So the newest three detections A, B and C are scored by how
far each sits from the other two:

```text
score A = distance(A, B) + distance(A, C)
score B = distance(B, A) + distance(B, C)
score C = distance(C, A) + distance(C, B)
```

The pose with the smallest score — the **medoid** — is used. A lone outlier
scores badly against the two that agree, so it is dropped. The result is always
a real measured pose, never an average that includes the bad one.

**Everyday wobble → a dead zone.**
Below the dead zone the pose is held completely still, so a resting avatar does
not shimmer.

**Genuine movement → smoothing.**
Above the dead zone the pose eases toward the new target instead of jumping.

Current settings:

```text
Medoid window       = 3 detections
Position dead zone  = 3 mm
Rotation dead zone  = 1 degree
Smoothing time      = 0.15 seconds
```

Two honest notes about these values:

- The dead zone is a **joint** test. The pose is held still only when the
  position change *and* the rotation change are both inside their limits; if
  either exceeds its limit, the full pose moves. Position and rotation are not
  filtered independently, and there is one smoothing time for both.
- 3 mm sits slightly **below** the measured stationary p95 of 3.47 mm, so a few
  percent of resting samples still pass through the dead zone. Raising it to
  4 mm would match the measurement; keeping 3 mm trades a little residual
  shimmer for slightly faster response. This is a tuning choice, not a
  measurement result.

## 10. Final processing chain

```text
Raw ID1 and ID2 marker poses
        |
        v
Reconstruct the common pose from each, and fuse what is available
        |
        v
Choose the medoid of the newest three detections   (rejects bad detections)
        |
        v
Hold still inside the dead zone                    (removes wobble)
        |
        v
Ease toward the new pose                           (smooths real movement)
        |
        v
Place the avatar
```

## 11. Limitations

- **The reference is ID0 itself, not ground truth.** Every number measures
  *agreement with ID0*, and section 6 showed ID0 has its own wobble and its own
  bad samples. True accuracy would need external motion capture.
- **The movement result rests on two recordings** that differ by nearly a factor
  of two. The size of the movement penalty is established; its exact value is
  not.
- **The stationary experiment cannot set the smoothing time.** It contains no
  movement, so it can measure noise but not lag. The smoothing time was chosen
  by eye and remains the least evidence-backed setting.

## 12. Reproducing the numbers

```bash
python analyze_moving_aruco.py aruco_raw_1785327929.csv
python analyze_moving_aruco.py aruco_raw_1785327343.csv
python analyze_hiding_aruco.py aruco_raw_1785330813.csv
```

Each script prints its table and writes a PNG next to the CSV. The scripts read
every logger version: older recordings carry `detected_count` and `<marker>_seen`
columns, while current ones simply leave the pose columns empty for a marker
that was not seen.

Five files, each with one job:

| File | Contains |
|---|---|
| `aruco_pose.py` | reading the CSV, pose arithmetic, error statistics |
| `aruco_plot.py` | PNG drawing only; affects no number |
| `analyze_moving_aruco.py` | experiment 2 (section 7) |
| `analyze_hiding_aruco.py` | experiment 3 (section 8) |

To follow the analysis, read `aruco_pose.py` and one experiment script.
`aruco_plot.py` can be ignored entirely — it only exists because matplotlib is
not installed on this machine.
