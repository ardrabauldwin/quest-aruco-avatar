# ArUco Pose Logger and Filter Analysis

Date: 29 July 2026

## 1. Purpose

The standalone `aruco_csv_logger.gd` records numerical ArUco poses for later
filter analysis. It does **not** record video and it does **not** modify
`main_3d.gd`.

Each completed OpenCV result becomes one CSV row containing:

- the logger time;
- the number of detected markers;
- the capture-aligned Quest camera pose;
- ID 0 (common), ID 1 (chest), and ID 2 (navel);
- position `x, y, z` in metres;
- rotation `qx, qy, qz, qw` as a quaternion;
- `seen=0` and empty pose fields when a marker was not detected.

## 2. Where the data comes from

Paul's C++ code creates one dictionary for each processed camera image:

```cpp
result[ids[i]] = lens_pose * Transform3D(basis, origin);
```

Conceptually:

```gdscript
{
    0: Transform3D(...), # common
    1: Transform3D(...), # chest
    2: Transform3D(...)  # navel
}
```

The logger copies this completed dictionary. It does not run OpenCV again.

```text
Quest camera image
        |
        v
Paul/OpenCV: detect markers and calculate 6-DoF
        |
        v
Dictionary {marker ID: Transform3D}
        |
        v
Standalone logger: one dictionary -> one CSV row
```

## 3. Simple code structure

The logger is intentionally divided into seven numbered sections.

| Section | Function | Responsibility |
|---|---|---|
| Settings | constants and exports | Recording time, marker IDs, node references |
| Recording state | private variables | File, timer, row number, last fingerprint |
| Start | `_ready()`, `_on_button()` | Connect right-controller A button |
| Main flow | `_process()` | Copy result, reject duplicate, save row |
| Safe copy | `_get_latest_opencv_result()` | Copy Paul's result while holding its mutex |
| File lifecycle | `_start_recording()`, `_stop_recording()` | Open and close the CSV |
| CSV conversion | `_save_result_as_csv_row()` and helpers | Convert `Transform3D` values into columns |

The complete main flow is:

```gdscript
func _process(_delta: float) -> void:
    var result := _get_latest_opencv_result()
    if result.is_empty():
        return

    if not _is_new_result(result):
        return

    if _recording:
        _save_result_as_csv_row(result.markers, result.camera_pose)
```

## 4. Why the mutex is used

OpenCV works on a worker thread. The mutex prevents the worker from replacing
the result while the logger is copying it:

```gdscript
result_mutex.lock()
var markers = detection_source.get("_result_markers").duplicate(true)
var camera_pose = detection_source.get("_result_cam_xform")
result_mutex.unlock()
```

The lock is held only during the copy.

## 5. Why the hash is used

Godot calls `_process()` about 72 times per second, while OpenCV normally
finishes only 8–12 results per second. The latest OpenCV result remains stored
between detections.

Without a fingerprint, the same result could be written several times:

```text
Godot frame 1 -> result A -> write A
Godot frame 2 -> still result A -> write A again
Godot frame 3 -> still result A -> write A again
```

The hash acts as a fingerprint:

```gdscript
var result_hash := hash(result)
if result_hash == _last_result_hash:
    return
```

Therefore each changed OpenCV result is written once.

## 6. Experimental procedure

1. Launch the Quest application.
2. Make the required markers visible.
3. Press A once on the right controller.
4. Keep the chosen experimental condition for 30 seconds.
5. The logger stops automatically.
6. Do not press B during raw logging because B performs calibration.

Files are stored as:

```text
user://aruco_raw_<timestamp>.csv
```

## 7. Stationary-test filter analysis

The recorded stationary file contained 260 OpenCV samples over 29.8 seconds.
All three markers were simultaneously detected in 234 samples.

For every synchronized sample, robust marker-to-navel offsets were calculated:

```gdscript
common_to_navel = common_pose.affine_inverse() * navel_pose
chest_to_navel = chest_pose.affine_inverse() * navel_pose
```

The navel was reconstructed independently from ID 0 and ID 1, then fused. Each
fused pose was compared with the robust stationary centre.

| Fused ID 0 + ID 1 error | Position | Rotation |
|---|---:|---:|
| Median | 0.81 mm | 0.19 degrees |
| 95th percentile | 2.63 mm | 0.46 degrees |
| 99th percentile | 7.55 mm | 2.06 degrees |
| Maximum | 9.60 mm | 2.46 degrees |

The active filter currently uses:

```gdscript
POSITION_DEAD_ZONE_M = 0.015
ROTATION_DEAD_ZONE_DEG = 3.0
SMOOTHING_TIME_S = 0.40
```

Comparison:

| Parameter | Current value | Evidence-based starting value |
|---|---:|---:|
| Position dead zone | 15 mm | 4–5 mm after outlier handling |
| Rotation dead zone | 3 degrees | approximately 1 degree |
| Smoothing time | 0.40 seconds | Must be selected from a movement test |

The stationary log can measure noise and suggest dead zones. It cannot measure
tracking delay, so it cannot determine the smoothing time by itself.

## 8. Main conclusions

- Normal fused common/chest noise is only a few millimetres and less than one
  degree.
- There is no evidence of continuously accumulating relative drift.
- ID 2 produced large errors immediately after a detection interruption, so
  calibration should use several stable samples rather than one frame.
- ID 2 should be used as the calibration reference and then removed from normal
  common/chest runtime fusion.
- Position and rotation should be filtered independently.
- A controlled movement recording is required before selecting the final
  smoothing time.

## 9. Short oral explanation

> Paul’s OpenCV code produces one dictionary of marker poses for each processed
> camera image. I added a separate logger node that safely copies this dictionary
> using the same mutex. A hash prevents the same stored result from being written
> more than once. When I press A, each new dictionary is converted into one CSV
> row for 30 seconds. The CSV contains positions and quaternion rotations for
> common, chest, and navel markers. No video is recorded, and the original
> detection script remains separate.

## 10. Relevant files

- `project/aruco_csv_logger.gd` — standalone logger
- `project/main_3d.tscn` — logger node and exported node paths
- `src/OpenCVProcessor.cpp` — Paul's OpenCV result dictionary
- `aruco_raw_1785317240_01.csv` — first stationary recording
