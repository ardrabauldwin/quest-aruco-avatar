# Model selection — corrected 3 October 2026

Use Dennis's existing `human_patient.glb` for the animated patient and his
`mannequin_scan.glb` for the calibration reference. The user rejected the older
GLB. Its replacement asset, scene, scale mapping and reference test have been
removed from the integration. The original older project is untouched.

Migrate behavior, not the old mesh: retain the optional calibrated multi-marker
adapter, newer compression-counting dependency and scenario integration described
in `PLACEMENT_COUNTING_MIGRATION.md`.

Do not transfer the older model's nudge, dimensions or contact-point coordinates.
The common-marker-to-sternum calibration must be measured for Dennis's model.
At the user's request, XR startup now uses the older robust collection rule;
the old 10 cm/10 degree viewer-bias cancellation controls post-placement XR
updates. Range scaling is not copied. See `VIEWER_GATE_MIGRATION.md`.

This supersedes the previous `NaReT_merged_with_original_GLB_20261003.zip` package.
