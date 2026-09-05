# Rest-filter experiments

Use two separate CSV recordings. One isolates stationary tracking noise and viewpoint bias; the
other isolates genuine mannequin movement and endpoint following.

## Shared preparation

- Use the current marker layout and current APK.
- Use the same Quest, app build, room and lighting for both recordings.
- Do not restart or recenter between recordings unless that fact is written in the notes.
- Keep all markers rigidly attached and do not recalibrate between recordings.

## Recording 1: stationary

Select the logger's `stationary` test type. Keep the mannequin completely fixed. Use the centre of
the common/ID0 marker as the viewpoint reference. Start at the front, then press X once for each
new phase and hold the requested viewpoint for 30 seconds:

1. `stationary_front`: head about 1.0 m directly in front of the marker.
2. `stationary_left_view`: move around the mannequin to about 45 degrees left while remaining
   about 1.0 m from the marker.
3. `stationary_right_view`: move to about 45 degrees right while remaining about 1.0 m away.
4. `stationary_high_view`: return to the front and place the headset about 30 cm above the normal
   front-view height.
5. `stationary_low_view`: front view, about 30 cm below the normal front-view height.
6. `stationary_far_view`: normal front-view height, about 1.5 m from the marker.

The label shown in Quest and written into every CSV row changes automatically. Avoid covering all
markers simultaneously. These distances are repeatable test geometry, not filter parameters. If a
marker cannot be detected at a specified viewpoint, move only enough to recover detection and note
the actual distance or angle.

At the measured 4.4 detections/s, this should provide about 396 detections. That gives the grid
many independent replay windows instead of letting one fortunate startup prefix decide the result.

## Recording 2: moving

Place tape marks for mannequin positions **A** and **B**, separated horizontally by exactly 105 mm
using half the 210 mm width of an A4 sheet. Because the common/ID0 marker is elevated on the chest,
use an accessible, repeatable base point rigidly connected to the mannequin for alignment with A
and B. With rigid translation and no rotation, the elevated common marker moves through the same
105 mm vector. Move the whole mannequin as one rigid object: do not lift, tilt or rotate it.

Photograph or sketch the two tape marks so the positions cannot be confused later. The tuning
script derives the numerical A-to-B direction from the recorded poses.

Select the logger's `moving` test type. Keep one recording running and advance the phase exactly
at each transition:

1. `stationary_A` at A for 30 seconds.
2. `moving_A_to_B`: translate the whole mannequin continuously from A to B over about 30 seconds.
   Spread the 105 mm movement across the phase; do not move quickly and then hold.
3. `stationary_B` at B for 30 seconds.
4. `moving_B_to_A`: translate it continuously from B back to A over about 30 seconds.
5. `stationary_A_return` at A for 30 seconds.

Target duration: about 150 seconds. At the measured 4.4 detections/s, each phase should contain
about 132 detections, enough for the largest 100-detection fallback candidate.

## Record in the experiment notes

- Exact displacement A to B in millimetres.
- Whether the mannequin returned exactly to the original tape marks.
- Any interval where a marker detached, bent, or was covered unexpectedly.
- Any accidental pause during a moving phase.
- Headset/app version and which physical Quest was used.
- Any restart, recenter, lighting change, or calibration change between recordings.

## One analysis command

Run every active filter-parameter search through `tune_filter.py`:

```powershell
python tune_filter.py path\to\calibration.csv path\to\stationary.csv path\to\moving.csv `
  --distance-mm 100
```

This one replay searches startup-rest counts and limits, medoid radius/window, position and
rotation dead zones, smoothing, prior pull, rest healing and tracking timeout. It follows partial
marker fusion, tracking loss/reacquisition and render-rate timing. `tune_rest_convergence.py` and
`basic_prior_search.py` are legacy and must not supply APK values.

The radius grid is `0.10, 0.15, 0.20, 0.25, 0.2864789, 0.30, 0.40, 0.50, 0.75 m`.
`0.2864789 m` exactly preserves the previous `15 mm / 3 degree` weighting. The output also prints
the radius as `1 degree = X mm`. The unified search scores:

- stationary confirmation and accepted rest-pose error;
- false convergence during continuous movement;
- movement lag from A to B and B to A;
- endpoint error at stationary B and returned stationary A;
- stationary position/rotation wobble;
- fallback frequency.

It writes every evaluated display configuration to `tune_filter_results.csv` and writes the
winning display and rest parameters to `tune_filter_best.txt`.

Do not call `2 mm`, `0.5 degrees`, or `50 detections` validated until these recordings have been
processed. They remain provisional runtime values.

The rest-acquisition grid searches initial counts `10, 15, 20, 25, 30, 40`, checkpoint intervals
`3, 5, 8, 10`, stable-check counts `2, 3, 4`, and fallbacks `40, 50, 60, 75, 100`, together with
the position and rotation stability limits. A setting's earliest confirmation is `initial +
interval x stable checks`.
