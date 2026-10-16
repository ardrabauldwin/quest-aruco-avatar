"""Retarget NVIDIA Kimodo motion (SOMA skeleton, BVH with T-pose rest) onto the
MakeHuman game_engine rig inside Blender. Used by tools/generate_humans.py.

Method: put the target rig into the source's rest pose by aiming each mapped
bone along the source bone's rest direction, then for every frame
    R_target(t) = R_source(t) * R_source_rest^-1 * R_target_aimed
in world space, bone by bone down the hierarchy. The hips carry the root
translation, scaled by leg length. Loops: `walk` is cut to one stride pair and
made to walk on the spot at constant speed; the other clips cross-fade their
end into their start.
"""
from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS_SOURCE = 30.0
FPS_TARGET = 24.0

SIDES = {"l": "Left", "r": "Right"}
# target bone: (source bone, target direction end, source direction end)
MAP: dict[str, tuple[str, str | None, str]] = {
    "pelvis": ("Hips", None, "Spine1"),
    "spine_01": ("Spine1", "spine_02", "Spine2"),
    "spine_02": ("Spine2", "spine_03", "Chest"),
    "spine_03": ("Chest", "neck_01", "Neck1"),
    "neck_01": ("Neck1", "head", "Head"),
    "head": ("Head", None, "HeadEnd"),
}
for s, S in SIDES.items():
    MAP.update({
        f"clavicle_{s}": (f"{S}Shoulder", f"upperarm_{s}", f"{S}Arm"),
        f"upperarm_{s}": (f"{S}Arm", f"lowerarm_{s}", f"{S}ForeArm"),
        f"lowerarm_{s}": (f"{S}ForeArm", f"hand_{s}", f"{S}Hand"),
        f"hand_{s}": (f"{S}Hand", f"middle_01_{s}", f"{S}HandMiddle1"),
        f"thigh_{s}": (f"{S}Leg", f"calf_{s}", f"{S}Shin"),
        f"calf_{s}": (f"{S}Shin", f"foot_{s}", f"{S}Foot"),
        f"foot_{s}": (f"{S}Foot", f"ball_{s}", f"{S}ToeBase"),
        f"ball_{s}": (f"{S}ToeBase", None, f"{S}ToeEnd"),
    })
    for finger, Finger in (("index", "Index"), ("middle", "Middle"), ("ring", "Ring"), ("pinky", "Pinky"), ("thumb", "Thumb")):
        last = 3 if finger == "thumb" else 4
        MAP[f"{finger}_01_{s}"] = (f"{S}Hand{Finger}1", f"{finger}_02_{s}", f"{S}Hand{Finger}2")
        MAP[f"{finger}_02_{s}"] = (f"{S}Hand{Finger}2", f"{finger}_03_{s}", f"{S}Hand{Finger}3")
        MAP[f"{finger}_03_{s}"] = (f"{S}Hand{Finger}3", None, f"{S}Hand{Finger}{last if finger != 'thumb' else 'End'}")


def _import(path: Path) -> bpy.types.Object:
    before = set(bpy.data.objects)
    bpy.ops.import_anim.bvh(filepath=str(path), global_scale=0.01, axis_forward="-Z", axis_up="Y",
        rotate_mode="NATIVE", update_scene_fps=False, update_scene_duration=False)
    source = next(o for o in bpy.data.objects if o not in before)
    source.animation_data.action.name = "kimodo_" + path.stem
    return source


def _world(obj: bpy.types.Object, name: str) -> Matrix:
    return obj.matrix_world @ obj.pose.bones[name].matrix


def _rest_world(obj: bpy.types.Object, name: str) -> Matrix:
    return obj.matrix_world @ obj.data.bones[name].matrix_local


def _order(rig: bpy.types.Object) -> list[str]:
    ordered, pending = [], [b for b in rig.data.bones if b.parent is None]
    while pending:
        bone = pending.pop(0)
        ordered.append(bone.name)
        pending.extend(bone.children)
    return [n for n in ordered if n in MAP]


def aim(rig, name: str, direction, toward: str | None = None) -> None:
    """Rotate one pose bone (armature space) so its tail, or the head of bone
    `toward`, points along `direction`."""
    bpy.context.view_layer.update()
    bone = rig.pose.bones[name]
    head = bone.head.copy()
    current = ((rig.pose.bones[toward].head if toward else bone.tail) - head).normalized()
    direction = Vector(direction)
    turn = current.rotation_difference(direction.normalized())
    bone.matrix = Matrix.Translation(head) @ turn.to_matrix().to_4x4() @ Matrix.Translation(-head) @ bone.matrix


def _target_in_source_rest(rig, source) -> dict[str, Quaternion]:
    """World rotation of each mapped target bone once aimed like the source rest pose."""
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    to_armature = rig.matrix_world.to_quaternion().inverted()
    for name in _order(rig):
        src, end_t, end_s = MAP[name]
        if name == "pelvis" or src not in source.data.bones or end_s not in source.data.bones:
            continue
        direction = source.data.bones[end_s].head_local - source.data.bones[src].head_local
        direction = (source.matrix_world.to_quaternion() @ direction)
        aim(rig, name, to_armature @ direction, end_t)  # end_t: the mapped child's head
    bpy.context.view_layer.update()
    return {n: _world(rig, n).to_quaternion() for n in _order(rig)}


def _sample(source, frames: int) -> tuple[list[dict[str, Quaternion]], list[Vector]]:
    rotations, hips = [], []
    names = [MAP[n][0] for n in MAP if MAP[n][0] in source.pose.bones]
    for frame in range(frames):
        bpy.context.scene.frame_set(frame + 1)
        rotations.append({s: _world(source, s).to_quaternion() for s in names})
        hips.append(_world(source, "Hips").translation.copy())
    return rotations, hips


def _heading(q: Quaternion, rest: Quaternion) -> float:
    forward = (q @ rest.inverted()) @ Vector((0, -1, 0))
    return math.atan2(forward.x, -forward.y)


def _walk_cycle(source, count: int) -> tuple[int, int]:
    """Two successive left-foot landings (lifted, then back on the ground) in the
    settled second half of the take: one full stride pair."""
    heights = []
    for frame in range(count):
        bpy.context.scene.frame_set(frame + 1)
        heights.append(_world(source, "LeftFoot").translation.z)
    ground = min(heights[count // 4:])
    lifted = ground + 0.04
    landings, airborne = [], False
    for i in range(count // 4, count):
        if heights[i] > lifted:
            airborne = True
        elif airborne and heights[i] < ground + 0.015:
            landings.append(i)
            airborne = False
    if len(landings) >= 2:
        return landings[-2], landings[-1]
    return count // 3, count // 3 + int(FPS_SOURCE * 1.1)


def bake(rig, bvh: Path, name: str, tail_seconds: float = 0.0, head_seconds: float = 0.0) -> tuple[bpy.types.Action, float]:
    """Returns (action on `rig`, forward speed in m/s for walk clips, else 0)."""
    source = _import(bvh)
    total = int(source.animation_data.action.frame_range[1])
    rest_target = _target_in_source_rest(rig, source)
    rest_source = {MAP[n][0]: _rest_world(source, MAP[n][0]).to_quaternion() for n in rest_target}
    rotations, hips = _sample(source, total)
    start, end = 0, total
    if name == "walk":
        start, end = _walk_cycle(source, total)
    elif tail_seconds > 0.0:
        start = max(0, total - int(tail_seconds * FPS_SOURCE))
    elif head_seconds > 0.0:
        end = min(total, int(head_seconds * FPS_SOURCE))
    rotations, hips = rotations[start:end], hips[start:end]
    # Face the rig's forward (-Y): undo the take's heading at the start.
    yaw = -_heading(rotations[0]["Hips"], rest_source["Hips"])
    turn = Quaternion((0, 0, 1), yaw)
    rotations = [{k: turn @ q for k, q in frame.items()} for frame in rotations]
    hips = [turn @ h for h in hips]
    # Scale root motion by leg length; walk on the spot at the clip's mean speed.
    source_height = _rest_world(source, "Hips").translation.z
    target_rest = _rest_world(rig, "pelvis").translation
    scale = target_rest.z / max(source_height, 1e-3)
    offsets = [(h - hips[0]) * scale for h in hips]
    speed = 0.0
    n = len(offsets)
    if name == "walk" and n > 1:
        drift = offsets[-1] - offsets[0]
        drift.z = 0.0
        speed = drift.length / ((n - 1) / FPS_SOURCE)
        offsets = [o - drift * (i / (n - 1)) for i, o in enumerate(offsets)]
    else:
        for o in offsets:
            o.x *= 0.3            # keep a little sway, never wander off the spot
            o.y *= 0.3
    # Seamless loop for everything but the walk (already a full cycle).
    # A one-off transition (head of a sequenced take) must not loop back.
    blend = 0 if name == "walk" or head_seconds > 0.0 else min(n // 3, int(0.6 * FPS_SOURCE))
    for i in range(blend):
        k = n - blend + i
        t = (i + 1) / blend
        t = t * t * (3 - 2 * t)
        rotations[k] = {s: q.slerp(rotations[0][s], t) for s, q in rotations[k].items()}
        offsets[k] = offsets[k].lerp(offsets[0], t)

    action = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = action
    to_armature = rig.matrix_world.inverted()
    armature_rotation = rig.matrix_world.to_quaternion().inverted()
    order = [b for b in _order(rig) if MAP[b][0] in rest_source]
    previous: dict = {}
    for i in range(n):
        frame = 1 + i * FPS_TARGET / FPS_SOURCE
        for bone in rig.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        for name_t in order:
            src = MAP[name_t][0]
            world = rotations[i][src] @ rest_source[src].inverted() @ rest_target[name_t]
            bpy.context.view_layer.update()
            pose = rig.pose.bones[name_t]
            head = pose.matrix.translation.copy()
            if name_t == "pelvis":
                head = to_armature @ (target_rest + offsets[i])
            pose.matrix = Matrix.Translation(head) @ (armature_rotation @ world).to_matrix().to_4x4()
        bpy.context.view_layer.update()
        for name_t in order:
            # Euler keys like every other clip of this rig; the previous frame keeps
            # the angles continuous so interpolation never spins the long way round.
            pose = rig.pose.bones[name_t]
            euler = pose.matrix_basis.to_quaternion().to_euler("XYZ", previous.get(name_t, pose.rotation_euler))
            previous[name_t] = euler
            pose.rotation_mode = "XYZ"
            pose.rotation_euler = euler
            pose.keyframe_insert("rotation_euler", frame=frame, group=name_t)
            if name_t == "pelvis":
                pose.keyframe_insert("location", frame=frame, group=name_t)
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    # The imported take must not travel into the GLB as a clip of its own.
    take = source.animation_data.action
    bpy.data.objects.remove(source, do_unlink=True)
    bpy.data.actions.remove(take)
    return action, speed
