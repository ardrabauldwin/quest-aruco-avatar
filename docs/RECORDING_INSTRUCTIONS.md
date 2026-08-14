# ArUco recording instructions

For whoever is wearing the headset. About 20 minutes for all four recordings.

The code that does the logging is [`project/aruco_csv_logger.gd`](../project/aruco_csv_logger.gd) —
the button handling is in `_on_right_button` / `_on_left_button`, the phase names are the
`*_PHASES` constants at the top, and the CSV columns come from `_make_header`.

## Controls

| button | what it does |
| --- | --- |
| Right **A** | start / stop recording |
| Left **X** | next phase — press between every step below |
| Left **Y** | change test type |

When you put the glasses on there is a text label floating in front of you showing the
current type and phase.

> **CHECK THIS FIRST.** Press **X** a few times before recording anything and make sure the
> phase number on that label actually changes. The left controller has fallen asleep before.
> If X does nothing, the recording is useless — none of the data gets labelled, and every row
> comes out with the same `phase_label`.

The mannequin lies on the **floor** for all of them. Keep both markers in view as much as
you can.

## Recording 1 — `calibration`

The mannequin never moves. **You** move.

Press **Y** until the label says `calibration`. Press **A** to start.
Hold each position about 15 seconds, press **X** between each:

1. `near` — stand close, about 0.5 m
2. `far` — back off to about 2 m
3. `left_side` — stand on the mannequin's left
4. `right_side` — stand on its right
5. `crouch` — kneel down low
6. `stand_tall` — stand up straight, look down

Press **A** to stop.

## Recording 2 — `headmotion`

The mannequin never moves and you stay in one spot.

Press **Y** until the label says `headmotion`. Press **A** to start.
About 15 seconds each, press **X** between each:

1. `still` — do not move your head at all
2. `slow` — turn your head slowly left and right
3. `medium` — a bit faster
4. `fast` — quick head turns, but keep the markers in view

Press **A** to stop.

## Recording 3 — `moving` (sliding)

**The important one.** Put a tape measure on the floor next to the mannequin first.

Press **Y** until the label says `moving`. Press **A** to start.

1. `stationary` — about 20 s, nobody touches it
2. press **X**, then slide the mannequin **left exactly 30 cm** along the tape
   (`moving_left` — press X as you *start* sliding)
3. press **X** when it has stopped — `stationary`, about 20 s
4. press **X**, then slide it back **right exactly 30 cm** (`moving_right`)
5. press **X** when it has stopped — `stationary`, about 20 s

Press **A** to stop.

> **Write down the distance actually slid, both times.** If it came out 28 cm and not 30,
> write 28. The real number is the point of this recording — it is the only thing that makes
> the filter's pull strength measurable instead of guessed.

## Recording 4 — `moving` again (tilting)

Same test type. Press **A** to start. Tilt the **whole body** — do not lift or move the
marker plates, or the recording measures nothing useful.

1. `stationary` — about 20 s flat on the floor
2. press **X**, tilt onto its **left side by about 20 degrees** and hold (`moving_left`, ~15 s)
3. press **X**, lower it flat — `stationary`, about 15 s
4. press **X**, tilt again to **about 45 degrees** and hold (`moving_right`, ~15 s)
5. press **X**, lower it flat — `stationary`, about 15 s

Press **A** to stop.

A phone level app lying on the chest is accurate enough. **Write down roughly what angles
you actually reached.** 20 and 45 are chosen deliberately: one under the filter's tilt limit
and one over it.

## Afterwards

Pull the CSV files off the headset and send them, plus a short note with:

- the sliding distances
- the tilt angles
- anything odd that happened (marker lost, someone walked through, controller acting up)

## What ends up in the CSV

33 columns per row, written by `_make_header`:

| column | meaning |
| --- | --- |
| `sample_id` | row counter, 0, 1, 2 … |
| `logger_ms` | headset clock in ms — what the filter uses for timing |
| `recording_ms` | ms since this recording started |
| `test_type` | `calibration` / `headmotion` / `moving` — set by **Y** |
| `phase_label` | `left_side`, `fast`, `moving_left` … — set by **X** |
| `camera_x/y/z/qx/qy/qz/qw` | where the headset was |
| `common_*` | marker ID0, same 7 columns |
| `chest_*` | marker ID1 |
| `navel_*` | marker ID2 |

An empty block of 7 means that marker was not seen in that frame. That is itself data —
please do not delete those rows in Excel.
