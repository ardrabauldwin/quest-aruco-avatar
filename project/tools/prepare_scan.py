"""Normalize the upstream textured CPR torso without changing its topology or texture.

Run: Blender --background --python tools/prepare_scan.py -- --preview
Optional --sternum-height 0.30 uniformly scales the native scan to that chest height.
Default preserves native proportions. Godot axes: Y up, head -Z, sternum X=0/Z=-.08.
"""
import argparse
import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "third_party/quest-aruco-avatar/project/assets/avatar/mannequin.glb"
OUTPUT = ROOT / "assets/models/mannequin_scan.glb"
parser = argparse.ArgumentParser()
parser.add_argument("--sternum-height", type=float, default=0.20117643)
parser.add_argument("--preview", action="store_true")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
scan = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
points = np.array([scan.matrix_world @ vertex.co for vertex in scan.data.vertices])
center = points.mean(axis=0)
# Principal axes computed and visually verified for the pinned upstream scan.
# Fixed axes avoid SVD sign ambiguity when rebuilding on another platform.
axes = np.array([
    [-0.9991573691, 0.0371543206, -0.0174381789],
    [-0.0364635997, -0.9985975623, -0.0383836366],
    [-0.0188398398, -0.0377154350, 0.9991109371],
])
points = (points - center) @ axes.T
points[:, 2] -= points[:, 2].min()
scale = args.sternum_height / 0.20117643
if not 0.1 <= scale <= 3.0:
    raise ValueError("Requested sternum height produces an unreasonable scale")
points[:, :2] *= -1  # Nose up, head Blender +Y / Godot -Z.
points *= scale
points[:, 0] -= 0.005 * scale
points[:, 1] += 0.055 * scale + 0.08
for vertex, coordinate in zip(scan.data.vertices, points):
    vertex.co = coordinate
scan.parent = None
scan.matrix_world = Matrix.Identity(4)
scan.name = "ScanTorso"
for obj in list(bpy.context.scene.objects):
    if obj != scan:
        bpy.data.objects.remove(obj, do_unlink=True)

root = bpy.data.objects.new("NaReTScan", None)
bpy.context.collection.objects.link(root)
scan.parent = root
root["source_repository"] = "https://github.com/ardrabauldwin/quest-aruco-avatar"
root["source_commit"] = subprocess.check_output(["git", "-C", str(ROOT / "third_party/quest-aruco-avatar"), "rev-parse", "HEAD"], text=True).strip()
root["source_file_sha256"] = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
root["license"] = "Unlicense (upstream repository); see docs/MODELS.md"
root["coordinate_system"] = "Godot Y up; head -Z; source-native scale unless explicitly overridden"

# Smooth, local morphs keep the head and scan boundaries fixed, with no split seam.
scan.shape_key_add(name="Basis")
for name, displacement in [("ChestBreath", 0.009), ("ChestCompression", -0.035)]:
    key = scan.shape_key_add(name=name)
    for index, coordinate in enumerate(points):
        x, y, z = coordinate
        weight = math.exp(-((x / (0.15 * scale)) ** 2 + ((y - 0.08) / (0.17 * scale)) ** 2) * 1.8)
        front_weight = min(1.0, max(0.0, (z / scale - 0.08) / 0.10))
        key.data[index].co.z += displacement * scale * weight * front_weight

anatomy = bpy.data.objects.new("Anatomy", None)
bpy.context.collection.objects.link(anatomy)
anatomy.parent = root
# Surface landmarks selected from the top-down scan. These are visual estimates,
# not patient calibration data. Eyes in the source scan are molded/mostly closed.
source_landmarks = {
    "Sternum": (-0.005, 0.055),
    "LeftEye": (0.035, -0.289),
    "RightEye": (-0.035, -0.289),
    "Mouth": (-0.005, -0.213),
    "Forehead": (-0.005, -0.34),
    "Nose": (-0.005, -0.262),
}
landmarks = {}
for name, (original_x, original_y) in source_landmarks.items():
    x = (-original_x - 0.005) * scale
    y = (-original_y + 0.055) * scale + 0.08
    nearby = points[(np.abs(points[:, 0] - x) < 0.012 * scale) & (np.abs(points[:, 1] - y) < 0.012 * scale)]
    z = float(nearby[:, 2].max()) + 0.002 * scale
    marker = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(marker)
    marker.parent = anatomy
    marker.location = (x, y, z)
    marker.empty_display_size = 0.01
    landmarks[name] = [round(x, 5), round(z, 5), round(-y, 5)]

bpy.ops.object.select_all(action="SELECT")
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", export_apply=False,
                          export_extras=True, export_morph=True, export_morph_normal=True)
minimum, maximum = points.min(0), points.max(0)
metadata = {
    "source_repository": root["source_repository"], "source_commit": root["source_commit"],
    "source_sha256": root["source_file_sha256"], "uniform_scale": scale,
    "godot_size_xyz_m": [float(maximum[0]-minimum[0]), float(maximum[2]-minimum[2]), float(maximum[1]-minimum[1])],
    "godot_landmarks_xyz_m": landmarks, "mesh_node": "ScanTorso",
    "blend_shapes": ["ChestBreath", "ChestCompression"],
}
(ROOT / "assets/models/mannequin_scan.json").write_text(json.dumps(metadata, indent=2) + "\n")
print("NARET_SCAN", json.dumps(metadata))

if args.preview:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.world.color = (0.22, 0.25, 0.28)
    bpy.ops.object.camera_add(location=(1.15 * scale, 1.30 * scale, 1.5 * scale))
    camera = bpy.context.object
    camera.rotation_euler = (Vector((0, 0.1, 0.10 * scale)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.18 * scale
    scene.camera = camera
    for position, energy in [((0, 0.3, 2), 140), ((-1, -0.5, 1.2), 60)]:
        bpy.ops.object.light_add(type="AREA", location=position)
        light = bpy.context.object
        light.data.energy = energy
        light.data.size = 2
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(ROOT / "build/scan.png")
    bpy.ops.render.render(write_still=True)
