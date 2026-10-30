# Archived orange/blue marker camera source

Preserved from the local naret-migration checkout on 29 October 2026. Original
file paths and byte hashes are in provenance.json. No runtime credentials or
saved patient calibration are included.

Orange replaces black, blue replaces white. The shader reconstructs RGB from
CameraServer luminance/chroma textures and segments hue; the CPU helper provides
an image conversion fallback. The provider uses the older CameraServer/readback
pipeline, not the current CameraX luminance-only addon. Full-resolution processing
was used for coloured-marker detail and can be substantially slower.

This folder is excluded from Godot resource scanning with .gdignore. It is source
for review/porting, NOT enabled in the standard APK. The current CameraX path
provides no hue; adding these files alone cannot enable colour segmentation.

For a deliberate port: restore the original scripts/tracking paths, review the
legacy tracker reference (do not overwrite the current tracker blindly), native
OpenCV API, camera permissions, camera intrinsics/resolution and camera-to-world
conversion. Preserve image/corner coordinates. Then run the provided conversion
test and validate on real orange/blue frames and Quest. The archived luminance
fallback assumes an intensity ordering and is not true hue detection. No claim
is made that this archived provider works unchanged with today's native addon.
