"""Bag-valve-mask for NaReT: bag with a 'squeeze' shape key, patient valve, mask dome and
cushion. Builds the mesh, renders two previews (relaxed, squeezed) and exports a GLB.

  blender --background --python build_bvm.py -- <out_dir>
"""
import math
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

OUT = Path(sys.argv[sys.argv.index("--") + 1]) if "--" in sys.argv else Path(".")
OUT.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"


def material(name, color, roughness=0.45, alpha=1.0, transmission=0.0, subsurface=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Alpha"].default_value = alpha
    if "Transmission Weight" in bsdf.inputs:
        bsdf.inputs["Transmission Weight"].default_value = transmission
    if "Subsurface Weight" in bsdf.inputs:
        bsdf.inputs["Subsurface Weight"].default_value = subsurface
        bsdf.inputs["Subsurface Radius"].default_value = (0.02, 0.02, 0.02)
    if alpha < 1.0:
        try:
            mat.surface_render_method = "BLENDED"
        except AttributeError:
            mat.blend_method = "BLEND"
    return mat


BAG = material("bvm_bag", (0.72, 0.80, 0.86), roughness=0.55, subsurface=0.4)
HARD = material("bvm_plastic", (0.20, 0.36, 0.62), roughness=0.35)
WHITE = material("bvm_white", (0.92, 0.93, 0.94), roughness=0.4)
DOME = material("bvm_dome", (0.85, 0.92, 0.97), roughness=0.08, alpha=0.32, transmission=0.6)
CUSHION = material("bvm_cushion", (0.70, 0.82, 0.95), roughness=0.6, alpha=0.75, subsurface=0.3)


def smooth(obj, levels=2):
    mod = obj.modifiers.new("subd", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for poly in obj.data.polygons:
        poly.use_smooth = True


def add_sphere(name, radius, scale, location, mat, segments=48, rings=32):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments, ring_count=rings, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def add_cylinder(name, radius, depth, location, mat, rotation=(0, 0, 0), vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=location, rotation=rotation, vertices=vertices)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new("bevel", "BEVEL")
    bevel.width = min(0.002, radius * 0.25)
    bevel.segments = 3
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def add_torus(name, major, minor, scale, location, mat):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=location, major_segments=64, minor_segments=24)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


# ---- mask: cushion rim at z=0 (patient's face), dome above, port on top
cushion = add_torus("MaskCushion", 0.052, 0.013, (1.0, 0.78, 0.9), (0, 0, 0.010), CUSHION)
dome = add_sphere("MaskDome", 1.0, (0.052, 0.040, 0.042), (0, 0, 0.012), DOME)
# cut the dome's lower half so it is a cup
bpy.context.view_layer.objects.active = dome
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.bisect(plane_co=(0, 0, 0.014), plane_no=(0, 0, 1), clear_inner=True)
bpy.ops.object.mode_set(mode="OBJECT")
solid = dome.modifiers.new("solid", "SOLIDIFY")
solid.thickness = 0.002
bpy.ops.object.modifier_apply(modifier=solid.name)
port = add_cylinder("MaskPort", 0.011, 0.022, (0, 0, 0.060), HARD)
port_ring = add_cylinder("MaskPortRing", 0.0135, 0.006, (0, 0, 0.072), WHITE)

# ---- patient valve: elbow turning from the mask upward to the bag axis (+Z)
valve_body = add_cylinder("ValveBody", 0.016, 0.034, (0, 0, 0.092), WHITE)
valve_cap = add_cylinder("ValveCap", 0.018, 0.010, (0, 0, 0.112), HARD)
exhaust = add_cylinder("ValveExhaust", 0.007, 0.016, (0.020, 0, 0.092), HARD, rotation=(0, math.pi / 2, 0))

# ---- bag: ellipsoid along +Z, 24 cm long, 12.5 cm wide, with a squeeze shape key
bag = add_sphere("Bag", 1.0, (0.0625, 0.0625, 0.120), (0, 0, 0.240), BAG, segments=64, rings=48)
smooth(bag, 1)
bpy.context.view_layer.objects.active = bag
bag.shape_key_add(name="Basis", from_mix=False)
squeeze = bag.shape_key_add(name="squeeze", from_mix=False)
for vert, target in zip(bag.data.vertices, squeeze.data):
    local = vert.co
    # grip from the +X side, strongest at the middle of the bag
    along = (local.z - 0.240) / 0.120
    profile = max(0.0, math.cos(along * math.pi / 2.0)) ** 1.2
    radial = Vector((local.x, local.y, 0.0))
    r = radial.length
    if r > 1e-6:
        side = max(0.0, local.x / r)  # 1 on the gripped side, 0 opposite
        dent = profile * (0.55 * side + 0.22)
        new_r = r * (1.0 - dent)
        target.co = Vector((local.x / r * new_r, local.y / r * new_r, local.z + profile * 0.004))
bag_neck = add_cylinder("BagNeck", 0.020, 0.016, (0, 0, 0.122), HARD)
# inlet valve and reservoir stub at the far end
inlet = add_cylinder("InletValve", 0.017, 0.024, (0, 0, 0.366), HARD)
inlet_cap = add_cylinder("InletCap", 0.019, 0.008, (0, 0, 0.380), WHITE)
nipple = add_cylinder("OxygenNipple", 0.004, 0.018, (0.016, 0, 0.372), WHITE, rotation=(0, math.pi / 2, 0))

parts = [cushion, dome, port, port_ring, valve_body, valve_cap, exhaust, bag, bag_neck, inlet, inlet_cap, nipple]
root = bpy.data.objects.new("BagValveMask", None)
bpy.context.collection.objects.link(root)
for obj in parts:
    obj.parent = root

# ---- preview renders
scene.render.engine = "BLENDER_EEVEE_NEXT" if hasattr(bpy.types, "SceneEEVEE") and "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 900
scene.render.film_transparent = False
world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.93, 0.94, 0.96, 1.0)
bg.inputs[1].default_value = 1.0
bpy.ops.object.light_add(type="SUN", location=(0.5, -0.6, 0.9))
sun = bpy.context.active_object
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
bpy.ops.object.light_add(type="AREA", location=(-0.4, 0.4, 0.6))
fill = bpy.context.active_object
fill.data.energy = 60.0
fill.data.size = 0.6
bpy.ops.object.camera_add(location=(0.62, -0.72, 0.38))
cam = bpy.context.active_object
cam.data.lens = 55
target = Vector((0.0, 0.0, 0.19))
direction = target - cam.location
cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
# a flat face plane so the mask is seen resting on a surface
bpy.ops.mesh.primitive_plane_add(size=0.6, location=(0, 0, -0.001))
plane = bpy.context.active_object
plane.data.materials.append(material("skin_plane", (0.80, 0.66, 0.58), roughness=0.7))

# The newly added key is active and pinned in background mode, so the relaxed render
# would show the squeeze. Unpin and go back to the basis before rendering.
bag.show_only_shape_key = False
bag.active_shape_key_index = 0
bag.data.shape_keys.key_blocks["squeeze"].value = 0.0
print("PIN", bag.show_only_shape_key, bag.active_shape_key_index)
print("SHAPE basis", bag.data.vertices[100].co, "squeeze", bag.data.shape_keys.key_blocks["squeeze"].data[100].co)
scene.render.filepath = str(OUT / "bvm_relaxed.png")
bpy.ops.render.render(write_still=True)
# Squeezed preview: with the key unpinned, the value drives the evaluated mesh.
bag.data.shape_keys.key_blocks["squeeze"].value = 1.0
bpy.context.view_layer.update()
scene.render.filepath = str(OUT / "bvm_squeezed.png")
bpy.ops.render.render(write_still=True)
bag.data.shape_keys.key_blocks["squeeze"].value = 0.0

# ---- export GLB (shape key kept: no modifier application at export)
for obj in [sun, fill, cam, plane]:
    bpy.data.objects.remove(obj)
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for obj in parts:
    obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT / "bag_valve_mask.glb"), export_format="GLB", use_selection=True,
                          export_apply=False, export_morph=True, export_morph_normal=False, export_yup=True)
print("BVM written to", OUT)
