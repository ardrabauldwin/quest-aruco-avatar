"""Original training props: AED with electrodes, and an anatomical heart.
Run: python3 tools/generate_aed_face.py, then Blender --background --python tools/generate_models.py

Coordinates: Blender Z up; glTF converts to Godot Y up. The AED lies flat on the
floor, front edge toward -Y, so Godot sees its front toward +Z.
Electrodes, buttons, LED and the cable port export as their own named nodes so
the app can move the pads onto the chest and light the device.
All geometry created here is MIT licensed with the project.
"""
import math
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector

OUT = Path(__file__).resolve().parents[1] / "assets/models"
OUT.mkdir(parents=True, exist_ok=True)


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.curves, bpy.data.metaballs):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def material(name, color, metallic=0.0, roughness=.55, emission=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    shader = m.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    if emission:
        shader.inputs["Emission Color"].default_value = (*emission, 1)
        shader.inputs["Emission Strength"].default_value = 1.0
    return m


def finish(o, mat, smooth=True):
    o.data.materials.clear()
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = smooth
    return o


def rounded_box(name, size, pos, mat, radius=.012, segments=4, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel = o.modifiers.new("Moulded edge", "BEVEL")
    bevel.width, bevel.segments, bevel.limit_method = radius, segments, "NONE"
    o.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    bpy.ops.object.modifier_apply(modifier="Weighted normals")
    finish(o, mat)
    if parent:
        o.parent = parent
    return o


def cylinder(name, radius, depth, pos, mat, rotation=(0, 0, 0), vertices=32, bevel=.0, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=pos, rotation=rotation, vertices=vertices)
    o = bpy.context.object
    o.name = name
    if bevel:
        mod = o.modifiers.new("Soft rim", "BEVEL")
        mod.width, mod.segments = bevel, 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
    finish(o, mat)
    for p in o.data.polygons:
        p.use_smooth = abs(p.normal.z) < .5
    if parent:
        o.parent = parent
    return o


def flat_shape(name, points, depth, pos, mat, parent=None, rotation=(0, 0, 0)):
    """Extrudes a 2D outline (XY, metres) into a thin raised emblem."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    verts = [bm.verts.new((x, y, 0)) for x, y in points]
    face = bm.faces.new(verts)
    geom = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [v for v in geom["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=(0, 0, depth))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    o.location = pos
    o.rotation_euler = rotation
    finish(o, mat, smooth=False)
    if parent:
        o.parent = parent
    return o


def heart_outline(size, samples=40):
    """Classic heart curve, scaled to `size` metres wide, centred."""
    points = []
    for i in range(samples):
        t = 2 * math.pi * i / samples
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        points.append((x / 34 * size, (y + 2.5) / 34 * size))
    return points


def bolt_outline(h):
    return [(v[0] * h, v[1] * h) for v in [(.12, .5), (-.18, -.02), (.02, -.02), (-.12, -.5), (.2, .06), (0, .06)]]


def text_mesh(name, body, size, pos, mat, parent=None, depth=.0008):
    bpy.ops.object.text_add(location=pos)
    o = bpy.context.object
    o.name = name
    o.data.body = body
    o.data.size = size
    o.data.extrude = depth
    o.data.align_x = "CENTER"
    o.data.align_y = "CENTER"
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.object
    finish(o, mat, smooth=False)
    if parent:
        o.parent = parent
    return o


def export(name, keep_separate=()):
    """Joins every mesh that shares a material and parent into one draw call, except
    the named nodes the app animates."""
    groups = {}
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH" or obj.name in keep_separate:
            continue
        key = (obj.parent.name if obj.parent else "", obj.data.materials[0].name)
        groups.setdefault(key, []).append(obj)
    for (_parent, mat), objects in groups.items():
        if len(objects) < 2:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.join()
        bpy.context.object.name = mat
    bpy.ops.export_scene.gltf(filepath=str(OUT / f"{name}.glb"), export_format="GLB",
        export_apply=True, export_yup=True, export_extras=True)
    print("NARET_PROP", name, flush=True)


# ---------------------------------------------------------------- AED
# Single-button public-access AED in the style of the common white/red devices:
# 256 x 250 x 67 mm housing, printed front (tools/generate_aed_face.py), on/off
# key, automatic-shock indicator, pad connector with lead, status LED, PULL tab
# for the electrode pack and a webbing strap. It lies face up next to the
# patient, top edge (+Y) away from the rescuer. Manufacturer marks are not
# reproduced; the face carries the NaReT label instead.
reset()
housing = material("AED housing white", (.72, .73, .75), 0, .42)
strap = material("AED strap", (.05, .055, .06), 0, .9)
key_grey = material("AED key grey", (.5, .52, .55), 0, .35)
key_green = material("AED key green", (.04, .4, .05), 0, .35)
lens = material("AED sensor", (.004, .004, .005), 0, .1)
connector_red = material("AED connector red", (.62, .02, .03), 0, .4)
led = material("AED led", (.05, .5, .08), 0, .2, emission=(.05, .5, .08))
ink = material("AED print dark", (.03, .03, .035), 0, .5)
ring = material("AED shock ring", (.62, .64, .68), 0, .3)
pad_foam = material("Electrode foam", (.93, .93, .9), 0, .8)
pad_gel = material("Electrode gel", (.05, .15, .45), 0, .25)
pad_print = material("Electrode print", (.6, .02, .015), 0, .5)
cable = material("Electrode cable", (.1, .11, .12), 0, .5)
face_image = bpy.data.images.load(str(OUT / "aed_face.png"))
face = bpy.data.materials.new("AED face print")
face.use_nodes = True
bsdf = face.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = .38
tex = face.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = face_image
face.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

W, D, T = .256, .25, .067


def at(x_mm, y_mm, z=0.0):
    """Face millimetres (origin top-left, y down) to device metres."""
    return ((x_mm - 128) / 1000, (125 - y_mm) / 1000, z)


def rounded_rect(w, h, r, samples=10):
    points = []
    for cx, cy, start in [(w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)]:
        for i in range(samples + 1):
            a = math.radians(start + 90 * i / samples)
            points.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return points


root = bpy.data.objects.new("AED", None)
bpy.context.collection.objects.link(root)
body = flat_shape("Housing", rounded_rect(W, D, .03), T, (0, 0, 0), housing, root)
bevel = body.modifiers.new("Moulded edge", "BEVEL")
bevel.width, bevel.segments, bevel.limit_method, bevel.angle_limit = .009, 6, "ANGLE", math.radians(40)
bpy.context.view_layer.objects.active = body
bpy.ops.object.modifier_apply(modifier=bevel.name)
for p in body.data.polygons:
    p.use_smooth = True
# Printed front: UVs straight from position, so the drawing lands in millimetres.
plate = flat_shape("Face", rounded_rect(W - .018, D - .018, .022), .0004, (0, 0, T), face, root)
plate.data.uv_layers.new(name="UVMap")
for loop in plate.data.loops:
    co = plate.data.vertices[loop.vertex_index].co
    plate.data.uv_layers.active.data[loop.index].uv = ((co.x + W / 2) / .256, 1 - (125 - co.y * 1000) / 256)
top = T + .0004
# Sensor window with its dark dome.
rounded_box("Sensor", (.022, .022, .002), at(130, 63, top + .001), lens, .004, 3, root)
dome = cylinder("Sensor dome", .0065, .003, at(130, 63, top + .003), lens, vertices=24, bevel=.0014, parent=root)
# On/off key: grey cap in a green ring with the power symbol.
cylinder("PowerButton", .011, .005, at(220, 125, top + .0025), key_grey, bevel=.0018, parent=root)
bpy.ops.mesh.primitive_torus_add(major_radius=.0125, minor_radius=.0012, location=at(220, 125, top + .002))
finish(bpy.context.object, key_green).parent = root
bpy.ops.mesh.primitive_torus_add(major_radius=.0045, minor_radius=.0007, location=at(220, 125, top + .0053))
finish(bpy.context.object, key_green).parent = root
rounded_box("Power bar", (.0014, .006, .0012), at(220, 122, top + .0058), key_green, .0005, 2, root)
# Ring around the automatic-shock print; the app lights it while a shock is due.
bpy.ops.mesh.primitive_torus_add(major_radius=.0158, minor_radius=.0011, location=at(220, 176, top + .0008))
shock = finish(bpy.context.object, ring)
shock.name = "ShockButton"
shock.parent = root
# Status display: its glass is a separate plane the app renders the pulse into.
bpy.ops.mesh.primitive_plane_add(size=1, location=at(220, 215, top + .0006))
screen = bpy.context.object
screen.scale = (.031, .033, 1)
bpy.ops.object.transform_apply(scale=True)
screen.name = "Screen"
screen.data.materials.append(lens)
screen.parent = root
# Status LED.
bpy.ops.mesh.primitive_uv_sphere_add(radius=.0026, location=at(188, 77, top + .0005), segments=16, ring_count=8)
status = finish(bpy.context.object, led)
status.name = "Led"
status.parent = root
# Electrode connector with its lead running over the top edge.
rounded_box("Connector", (.026, .026, .011), at(220, 65, top + .0055), connector_red, .004, 4, root)
rounded_box("Connector label", (.01, .006, .0006), at(220, 67, top + .011), housing, .001, 2, root)
port = bpy.data.objects.new("Port", None)
bpy.context.collection.objects.link(port)
port.location = at(220, 58, top + .008)
port.parent = root
lead_curve = bpy.data.curves.new("Connector lead", "CURVE")
lead_curve.dimensions = "3D"
lead_curve.bevel_depth, lead_curve.bevel_resolution = .0022, 3
spline = lead_curve.splines.new("BEZIER")
spline.bezier_points.add(2)
for point, co in zip(spline.bezier_points, [at(220, 54, top + .008), at(232, 20, top + .006), at(240, -4, T * .55)]):
    point.co = co
    point.handle_left_type = point.handle_right_type = "AUTO"
lead = bpy.data.objects.new("Connector lead", lead_curve)
bpy.context.collection.objects.link(lead)
bpy.context.view_layer.objects.active = lead
bpy.ops.object.select_all(action="DESELECT")
lead.select_set(True)
bpy.ops.object.convert(target="MESH")
finish(bpy.context.object, cable).parent = root
# PULL tab of the electrode pack, sticking out of the right flank.
tab = flat_shape("Pull tab", [(0, -.013), (.024, -.013), (.034, 0), (.024, .013), (0, .013)], .0028, (W / 2 - .004, -.021, T * .45), key_grey, root)
text_mesh("Pull label", "PULL", .0085, (W / 2 + .015, -.021, T * .45 + .0034), ink, root, .0004)
# Webbing strap, lying flat past the top edge where the device was set down.
strap_curve = bpy.data.curves.new("Strap", "CURVE")
strap_curve.dimensions = "3D"
strap_curve.extrude, strap_curve.bevel_depth, strap_curve.bevel_resolution = .011, .0018, 2
spline = strap_curve.splines.new("BEZIER")
spline.bezier_points.add(2)
for point, co in zip(spline.bezier_points, [(-.098, D / 2 - .006, T * .5), (0, D / 2 + .05, .006), (.098, D / 2 - .006, T * .5)]):
    point.co = co
    point.tilt = math.pi / 2
    point.handle_left_type = point.handle_right_type = "AUTO"
strap_obj = bpy.data.objects.new("Strap", strap_curve)
bpy.context.collection.objects.link(strap_obj)
bpy.context.view_layer.objects.active = strap_obj
bpy.ops.object.select_all(action="DESELECT")
strap_obj.select_set(True)
bpy.ops.object.convert(target="MESH")
finish(bpy.context.object, strap).parent = root
for side in (-1, 1):
    rounded_box("Strap lug", (.03, .016, .02), (side * .098, D / 2 - .004, T * .5), key_grey, .005, 3, root)
# Two adult electrodes, hidden in the pack until they are applied.
for name in ("PadRight", "PadLeft"):
    pad = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(pad)
    pad.parent = root
    pad.location = (-.07 if name == "PadRight" else .07, -D / 2 - .08, .002)
    rounded_box(name + " foam", (.12, .09, .002), (0, 0, .001), pad_foam, .02, 3, pad)
    rounded_box(name + " gel", (.1, .07, .0012), (0, 0, -.0004), pad_gel, .016, 3, pad)
    flat_shape(name + " icon", heart_outline(.025), .0005, (.035, .02, .002), pad_print, pad)
    cylinder(name + " lead", .004, .02, (0, .045, .003), cable, rotation=(math.pi / 2, 0, 0), vertices=12, parent=pad)
export("aed", keep_separate=("ShockButton", "PowerButton", "Led", "Screen"))


# ---------------------------------------------------------------- Heart
# Organic single mesh: ellipsoids for the chambers and chains of spheres for the
# great vessels, fused by a voxel remesh and relaxed. Z runs base (up) to apex,
# +X is the patient's left, -Y faces the sternum. About 12 cm long like an adult
# heart; the origin sits in the ventricle mass.
reset()
myo = material("Myocardium", (.46, .05, .06), 0, .42)


def lump(center, radii, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=center, rotation=rotation)
    o = bpy.context.object
    o.scale = radii
    return o


def vessel(points, radius):
    parts = []
    for a, b in zip(points, points[1:]):
        a, b = Vector(a), Vector(b)
        steps = max(1, int((b - a).length / (radius * .6)))
        for i in range(steps):
            parts.append(lump(a.lerp(b, i / steps), (radius,) * 3))
    parts.append(lump(points[-1], (radius,) * 3))
    return parts


tilt = (math.radians(-18), math.radians(28), 0)                  # apex down, left, forward
parts = [lump((0, 0, 0), (.052, .044, .068), tilt)]               # ventricles
parts.append(lump((.024, -.014, -.052), (.032, .028, .036), tilt))  # apex
parts.append(lump((-.024, -.018, .006), (.04, .032, .05), tilt))  # right ventricle, anterior
parts.append(lump((-.042, .01, .046), (.028, .026, .03)))         # right atrium
parts.append(lump((.022, .03, .046), (.03, .022, .022)))          # left atrium
parts += vessel([(0, -.004, .05), (-.003, -.001, .07), (.004, .006, .086), (.018, .014, .093),
                 (.032, .022, .088), (.04, .028, .074), (.042, .032, .056)], .012)   # aortic arch
parts += vessel([(.016, -.024, .05), (.022, -.018, .074), (.036, -.01, .08)], .0115)  # pulmonary trunk
parts += vessel([(-.046, .014, .064), (-.046, .016, .09)], .0105)                      # superior vena cava
bpy.ops.object.select_all(action="DESELECT")
for part in parts:
    part.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.join()
heart = bpy.context.object
heart.name = "Heart"
remesh = heart.modifiers.new("Fuse", "REMESH")
remesh.mode, remesh.voxel_size = "VOXEL", .0035
bpy.ops.object.modifier_apply(modifier=remesh.name)
smooth = heart.modifiers.new("Tissue", "SMOOTH")
smooth.factor, smooth.iterations = .8, 12
bpy.ops.object.modifier_apply(modifier=smooth.name)
decimate = heart.modifiers.new("Budget", "DECIMATE")
decimate.ratio = min(1.0, 3000 / max(1, len(heart.data.polygons)))
bpy.ops.object.modifier_apply(modifier=decimate.name)
finish(heart, myo)
bpy.ops.object.shade_smooth()
export("heart")
