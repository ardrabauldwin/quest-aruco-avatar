# Experimental checkpoint updates

The default remains the existing viewer gate. To compare the experimental version,
set `SpatialAnchor.checkpoint_updates = true` in a separate scene copy, or launch:

```powershell
godot --path . -- --placement-checkpoints
```

This source option is not a new APK and has not been installed on Quest.

After initial placement, full marker evidence, a settled head and the existing
1.8 m range rule are required. Head movement includes all rotation (pitch/yaw/roll)
using the existing 0.3 s history, 0.15 m/s, 20 degrees/s and 0.5 s quiet settings.
Those settings are retained for comparison, not newly validated.

Fresh candidate poses are estimated at 30, 33, 36, 39, 42... detections. Each uses
median position and rotation medoid. Four stable comparisons within the existing
1.5 mm / 1 degree startup tolerances are required. The newest three readings must
also agree with each estimate, preventing a cumulative median from hiding ongoing
motion. The first possible confirmation is 42 detections. After 100, retain the
latest 100 samples, continue checking every three detections, and never force
acceptance. This bounded rolling history differs from the startup fallback.

Missing evidence, movement or excessive range discards the pending candidate.
Duplicate and older timestamps do not count. No 10 cm / 10 degree bias is subtracted,
and no 30 cm / 25 degree bypass is used. Initial startup is unchanged, including
its existing 100-reading fallback; this experiment changes later updates only.

On confirmation, the candidate becomes the remembered target. Render-frame
exponential smoothing (existing 1.2 s time constant) moves toward it. The legacy
five-reading smoother, 2 s rest pull and 8 cm / 8 degree rest-replacement rules
are bypassed in this mode: they cannot fight the confirmed target. Further raw
readings only form the next candidate; they cannot drag the patient meanwhile.
Movement, evidence loss or excessive range stops an ongoing transition. Height
continues to use the existing startup/floor/chest rules. No calibration is changed.

This is a consistency experiment, not a side-view depth correction. A persistent
wrong pose can still be confirmed. Compare stationary front/side/head-tilt cases,
compression occlusion and measured mannequin movements against the default mode.
Measure unwanted drift, physical alignment error and confirmation delay. Neither
the sample count nor tolerance is claimed to be optimal.
