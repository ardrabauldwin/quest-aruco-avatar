# Thursday 1 October 2026: v61 without the 0.937 focal reduction

This folder contains the **exact three source/text assets extracted from the working Thursday APK**, not the later stereo implementation currently in the development working tree.

Download the signed APK and the original Friday base from the [release](https://github.com/ardrabauldwin/quest-aruco-avatar/releases/tag/apk-20261001-v61-no0937-saved-nudge).

## What changed

- `no0937_main.gd` subclasses the original v61 main script. Detection uses fx=877.06583568 and fy=878.33004836, adjusted for the existing half-resolution image processing. The earlier 0.937 focal reduction is removed.
- `no0937_main.tscn` preserves the original scene and selects that subclass. It saves the final Thursday rig-local nudge: (-0.010868, 0.051197, 0) metres; yaw +0.2993167686005078 degrees. `use_saved_yaw=false` selects this startup default.
- `main_3d.tscn.remap` redirects the original scene to this text scene.
- Floor locking, marker fusion, motion gate and smoothing remain inherited from the Friday base.
- **The separate beyond-1.2-m range correction remains. This is not a build with all range corrections disabled.**

Comparing every uncompressed ZIP entry with the original Friday APK found exactly these three changes and no removals, excluding signing metadata. All original compiled scripts and native libraries remain unchanged. Hashes are in `manifest.json`.

## Reproduce the patch

This is an APK overlay, **not a complete reconstruction of the original Friday source checkout**. The repository's current `project/` should not be assumed to export this exact APK. Download the original base APK from the release and run:

```text
python releases/v61_no0937_20261001/build_overlay.py path/to/quest_v61_derived_placement_20260925.apk path/to/unsigned.apk
zipalign -p -f 4 path/to/unsigned.apk path/to/aligned.apk
apksigner sign --ks YOUR_KEYSTORE --out path/to/signed.apk path/to/aligned.apk
apksigner verify path/to/signed.apk
```

Signing credentials are deliberately not included. Installing over an existing app requires a matching signing key. Signing/ZIP metadata can change the whole-file hash; the asset contents are reproducible.

## Verification and limits

The signed Thursday APK was installed and launched on 1 October; the detector ran. No marker was visible during the final startup check, so that check did not establish visual alignment after restart. The saved nudge came from that day's final walk. This release does not claim that scaling was necessary or that side drift is solved. Later placement redesign proposals are not implemented here.
