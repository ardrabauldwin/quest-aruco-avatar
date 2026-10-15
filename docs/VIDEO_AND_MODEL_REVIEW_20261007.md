# Video and patient model review, 7 October 2026

Reviewed headset recording `de.uni_greifswald.naret.cprwitness-20261007-114438-0.mp4` (17.53 seconds). Local copy: `build/review-20261007-114438.mp4`; sampled frames: `build/video-review-montage.jpg`.

## Transparency

Both implementations duplicate materials and use `BaseMaterial3D.TRANSPARENCY_ALPHA`. They do not produce the same appearance:

- Original `project/avatar_rig_navel.gd`: `alpha = 1 - avatar_transparency`; current source default transparency 0.60, hence opacity 0.40. `project/main_3d.tscn` does not override that default. Applies a white tint.
- Current human patient: material opacity 0.75; retains textured skin and the clinical pallor tint. Alpha is preserved when pallor updates.
- These source settings establish the current defaults, not the identity/settings of every historical APK.

The video visibly shows physical markers/mannequin through the human overlay and overlapping face details. The human also has separate teeth, eyes, eyelashes and clothing surfaces. Alpha blending can expose these layers and the underlying mannequin together. The footage does not isolate which layer causes each face artifact; stronger opacity alone does not reproduce the original scan's appearance.

## Geometry

Measured triangle vertices with `tools/compare_patient_dimensions.gd`; skeleton deformation is included for the human. Results: `build/patient_dimensions_comparison.json`.

| Region | Width | Length | Overall depth |
|---|---:|---:|---:|
| Original scan with current `main_3d.tscn` mounting scale | 37.50 cm | 54.00 cm | 19.80 cm |
| New human: head to pelvis plane, including arms within that crop | 52.10 cm | 82.16 cm | 28.07 cm |
| New human: full body | 52.10 cm | 176.00 cm | 32.58 cm |

The original mount has axis scales 0.6872449, 0.7052474 and 0.6681291. The human model's scale is (1,1,1); it is an independently generated adult model, not a scaled original scan. No saved `calibration.cfg` was returned by the connected app's `run-as ... find files -name calibration.cfg` check during this review.

The head-to-pelvis crop is explicitly defined by the human pelvis bone; the original scan's crop is different. These rows are **not matching anatomical regions**, so their length ratio must not be used as a torso scaling factor. Overall depth includes facial/body extrema and is not the marker-plane-to-back measurement discussed in older notes.

The earlier physical dimensions were not transferred as fitting constraints to this patient. They were recovered from the user's 8 September conversation on rechecking:

> "our origianl manequin is 53 to 54 cm and 37.5 is its sidewazs or shoulder to shoudler"

The user initially requested 57 cm, then corrected the real mannequin measurement to 53–54 cm and 37.5 cm shoulder-to-shoulder, and authorized separate length and width adjustments. Thus **54 cm length and 37.5 cm shoulder width** are the previously used fitting targets; 57 cm is superseded. The supplied length is the mannequin's overall head-and-torso length, not a shoulder-to-waist measurement. No measured torso thickness was supplied in that message.

Next fitting step: match corresponding shoulder, sternum and lower-torso landmarks on the human using these existing physical targets. Do not use full-body height or the head-to-pelvis crop to infer torso alignment. Physical floor accuracy cannot be established in centimetres from this video alone.

No rendering, scaling or tracking code was changed by this review.
