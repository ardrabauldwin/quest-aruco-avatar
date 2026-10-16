# Rigged human characters

The primary digital patient and bystanders are actual anatomically modeled MakeHuman humanoids, generated and posed in **Blender 5.2.1 with MPFB 2.0.14 (20260225)**. The physical mannequin scan remains a registration reference. It is not used as the human avatar.

| Asset | Character | Adult height | Triangles | Meshes |
| --- | --- | ---: | ---: | ---: |
| `human_patient.glb` | Supine adult man, exposed training chest, navy shorts | 1.76 m | 41,406 | 7 |
| `human_bystander.glb` | Adult woman, brown ponytail, burgundy shirt, jeans and shoes | 1.70 m | 37,772 | 8 |
| `human_bystander_male.glb` | Adult man, short hair, olive shirt, jeans and shoes | 1.78 m | 35,346 | 8 |

All three have a **real, weighted 53-bone MakeHuman `game_engine` armature**. The mesh includes modeled facial anatomy, fingers, toes, a photographic skin texture, separate fitted eyes, brows, lashes, teeth and hair. Clothing is skinned to the same armature. MakeHuman helper cages, joint cubes and unused vertex groups are removed before export. Weights are exported with the four strongest influences per vertex, normalized for glTF/Quest.

The GLBs embed their textures. Source images are capped at 2048 pixels for skin and 1024 pixels for accessories. Skin, clothing, eyes and teeth use opaque materials; hair/brows/lashes use alpha cutout. Roughness is set per material in `normalize_gltf` (skin 0.5, eyes 0.08, cloth ~0.85). Bystanders stand with arms hanging in front of the hips; the `anxious` clip clasps the hands in front of the chest. The patient's skin is tinted grey-blue at runtime while in arrest and warms up after ROSC (`NaretMannequin._apply_pallor`). Treating skin as alpha-blended introduces transparent-triangle sorting artifacts in Godot and must not be restored.

## Animation API

Find the imported `Skeleton3D` and `AnimationPlayer` recursively under the model instance. The armature object is `HumanRig`. Mesh nodes are `PatientBody` or `BystanderBody`; Blender datablock names may differ.

| Character | Exact animation names |
| --- | --- |
| Patient | `idle`, `breathing`, `compression` |
| Bystanders | `idle`, `talk`, `anxious`, `relief` |

The patient's **idle is completely still**, with zero breathing and compression weights. `breathing` and `compression` are explicit training effects. They do not imply circulation, successful CPR or patient recovery. Bystander animations use real spine/head/arm rotations. `talk` also contains a varying mouth morph; these are authored example gestures, not captured human motion.

The body mesh exposes three blend shapes: `breathing`, `compression`, `mouth_open`, each in the range 0–1. Patient breathing raises the anterior thorax; compression deforms the sternum region smoothly inward. Clothing masks remove the concealed torso from bystanders, whose chest motion is primarily skeletal. These visual deformations do not measure real compression depth.

Blender's current `NLA_TRACKS` export path produced constant action slots in this environment. The generator uses `ACTIONS` and then joins each skeleton action with its corresponding `*_morphs` action into a single standard glTF animation. Verification checks the actual binary animation samples: patient compression/breathing vary from 0 to 1 and back; bystander talk contains five changing bone-rotation tracks. This avoids accepting clips that exist by name but contain no movement.

## Coordinate system and landmarks

Godot units are meters. Bystanders stand with their feet at ground level and face +Z. The patient lies supine with the head toward −Z, feet toward +Z and chest toward +Y. The lower sternum is centered at X=0 and Z=−0.08. Its exact Y coordinate is provided in the generated metadata, because the adult chest thickness differs from the physical training mannequin.

Five named nodes are attached to the appropriate bones: `Sternum`, `Mouth`, `Forehead`, `EyeLeft`, `EyeRight`. Sternum and face landmarks use mesh surface intersections; eye landmarks use the actual fitted eyeball geometry. [`human_models.json`](../assets/models/human_models.json) contains the exported marker coordinates, complete bone names, source assets, triangle counts and SHA-256 hashes.

Align the model's `Sternum` landmark to the physical scan's sternum using the calibration adapter. Physical CPR interaction zones remain attached to the real mannequin's coordinate system. Do not move clinical collision zones to compensate for visual anatomy. Core bone names are `Root`, `pelvis`, `spine_01`, `spine_02`, `spine_03`, `neck_01`, `head`, and paired `clavicle`, `upperarm`, `lowerarm`, `hand`, `thigh`, `calf`, `foot`, `ball` names with `_l`/`_r` suffixes; finger chains are also present.

## Editable Blender sources and regeneration

Packed source projects are produced under ignored `build/source/`:

- `human_patient.blend`
- `human_bystander.blend`
- `human_bystander_male.blend`

These contain the editable armature, vertex groups, textures, shape keys and authored actions. They are development artifacts and are excluded from the APK. Open an action in Blender's Action Editor to edit it; the NLA tracks are muted to keep the default pose still. The exported clinical meshes are already fitted and cleaned; regenerate to change MPFB body macros.

Install/enable the official [MPFB extension](https://extensions.blender.org/add-ons/mpfb/) in Blender, then run:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/generate_humans.py
```

Use `-- --only patient`, `-- --only female` or `-- --only male` for one character. The first run downloads the official 267 MB CC0 system asset pack into ignored `.cache/makehuman/`. Subsequent runs use that cache. No synthesis model, asset pack, Blender installation or MPFB addon is packaged on Quest. Studio preview renders are written beside the cached Blender projects.

After generation, run the ordinary Godot import and test suite, including `tests/test_models.gd`, then visually inspect the application render. Performance on a worn Quest still requires device measurement; triangle counts and correct skinning alone do not establish 72 FPS.

## Source and license

The MakeHuman base mesh and every selected skin, clothing, eye, teeth, eyebrow, eyelash and hair asset were explicitly released under **CC0-1.0**. The original files carry the September 2020 CC0 notice naming Data Collection AB, Joel Palmius and Jonas Hauquier. The generated humanoid GLBs are provided under CC0-1.0; the generator and runtime integration follow the project's MIT license. Blender/MPFB are separate creation tools and are not included in the app.

Authoritative sources:

- [MakeHuman system asset pack and per-asset CC0 declarations](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html)
- [Official MPFB source and scripting examples](https://github.com/makehumancommunity/mpfb2/tree/master/script_samples)
- [MakeHuman rigging documentation](https://static.makehumancommunity.org/mpfb/docs/characters/rig.html)
- [CC0 1.0 Universal dedication](https://creativecommons.org/publicdomain/zero/1.0/)

No Mixamo animation, Ready Player Me asset or model of uncertain local provenance is included in these characters.
