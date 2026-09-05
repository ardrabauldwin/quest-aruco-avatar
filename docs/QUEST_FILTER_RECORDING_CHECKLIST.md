# Quest filter-recording checklist

Three recordings are required:

1. One `stationary` CSV.
2. One `moving` CSV.
3. One `compressions` CSV.

## Controller buttons

- **Right-controller A:** start or stop a recording.
- **Left-controller X while stopped:** select the test type.
- **Left-controller X while recording:** advance to the next hard-coded phase.
- **Left-controller Y:** optional alternative for selecting the test type.

The current test and phase appear inside Quest. Do not type labels manually.

## Before recording

1. Install the newly built APK containing the labelled logger.
2. Use the existing calibration and current rigid marker arrangement.
3. Check that all markers are detected.
4. Do not recenter or restart Quest between the two recordings.

## Recording 1: stationary viewpoints

The mannequin must not move. Only the headset wearer changes position. Use the centre of the
common/ID0 marker as the viewing reference.

1. While stopped, press **X** until the test displayed in Quest is `stationary`.
2. Stand about 1.0 m directly in front of the common marker.
3. Press **A**. Recording starts at `stationary_front`.
4. Hold the front view for 30 seconds.
5. Press **X**. Move to about 45 degrees left, approximately 1.0 m from the common marker, and hold
   for 30 seconds. The label is `stationary_left_view`.
6. Press **X**. Move to about 45 degrees right, approximately 1.0 m away, and hold for 30 seconds.
   The label is `stationary_right_view`.
7. Press **X**. Return to the front and move the headset approximately 30 cm higher. Hold for
   30 seconds. The label is `stationary_high_view`.
8. Press **X**. Move the headset approximately 30 cm below the normal front-view height. Hold for
   30 seconds. The label is `stationary_low_view`.
9. Press **X**. Return to normal height and move approximately 1.5 m from the common marker. Hold
   for 30 seconds. The label is `stationary_far_view`.
10. Press **A** to stop recording.

## Recording 2: mannequin movement

### Define A and B using an accessible rigid reference point

The common/ID0 marker is elevated on the chest, so do not try to project its centre onto the floor.
Choose one clearly repeatable point on the mannequin that is close to the supporting surface, such
as a base corner or a taped pointer. The point must be rigidly connected to the marker arrangement.

1. Fold the 210 mm width of an A4 sheet in half to make a 105 mm reference.
2. Put the mannequin in its starting pose and align the chosen base point with **A**.
3. Place **B** exactly 105 mm horizontally from A using the half-width of the A4 sheet.
4. At the endpoint, align the same chosen base point with B.

Provided that the complete mannequin translates rigidly without rotating, lifting or bending,
every point on it—including the elevated common marker—moves by the same 105 mm vector. Record
which physical base point was used so the placement can be repeated.

```text
wearer's left

B  <---------- 105 mm ----------  A
base point at B                    base point starts at A
```

Move the whole mannequin rigidly. Do not rotate, tilt or lift it. Keep the headset approximately
stationary and keep the markers visible.

### Exact button sequence

1. While stopped, press **X** until the test displayed in Quest is `moving`.
2. Align the chosen rigid base point with A.
3. Press **A** to start recording. The label is `stationary_A`.
4. Keep the mannequin at A for 30 seconds.
5. Press **X** exactly when movement begins. The label becomes `moving_A_to_B`.
6. Move continuously from A to B over approximately 30 seconds. Spread the movement across the
   complete interval; do not move quickly and then wait.
7. When the chosen base point reaches B, press **X**. The label becomes `stationary_B`.
8. Keep the mannequin at B for 30 seconds.
9. Press **X** exactly when the return movement begins. The label becomes `moving_B_to_A`.
10. Move continuously from B back to A over approximately 30 seconds.
11. When the chosen base point reaches A, press **X**. The label becomes
    `stationary_A_return`.
12. Keep the mannequin at A for 30 seconds.
13. Press **A** to stop recording.

## Recording 3: chest compressions

The mannequin stays in place; you kneel beside it in the real CPR position. This recording
captures what compressions actually do to the markers: occlusion by hands and arms, markers
flickering in and out between compressions, and the whole mannequin rocking.

1. While stopped, press **X** until the test displayed in Quest is `compressions`.
2. Kneel at the mannequin's side in compression position, hands off the chest.
3. Press **A** to start recording. The label is `still_before`.
4. Hold still for 30 seconds with the markers visible.
5. Press **X** exactly when you begin compressions. The label becomes `compressions`.
6. Perform continuous chest compressions at a realistic rate (100-120 per minute) for about
   60 seconds. Do not try to keep the markers visible - real occlusion is the point.
7. Press **X** exactly when you stop. The label becomes `still_after`.
8. Hold still for 30 seconds.
9. Press **A** to stop recording.

## Write down after each take

- CSV filename and whether it is the stationary or moving recording.
- Confirmed A-to-B distance: 105 mm.
- Which rigid base point was used and whether it returned exactly to A.
- Any accidental marker obstruction, incorrect button press, pause or tracking loss.

If a button is pressed incorrectly, repeat that complete recording rather than editing its labels.
