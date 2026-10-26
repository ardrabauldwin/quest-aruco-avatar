#!/usr/bin/env python3
"""Build real MakeHuman humanoids with weighted rigs in Blender, then export GLB.

Blender 5.2 + installed MPFB extension required. Optional CC0 assets are fetched
from the official MakeHuman mirror into ignored .cache, never into the APK.
Run: Blender --background --python tools/generate_humans.py
"""
from __future__ import annotations
import argparse
import hashlib
import importlib
import json
import math
from pathlib import Path
import subprocess
import shutil
import struct
import sys
import zipfile

import bpy
from mathutils import Vector, Matrix, Quaternion

sys.path.insert(0, str(Path(__file__).resolve().parent))
import retarget_kimodo  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache/makehuman'
ASSETS = CACHE / 'assets'
PACK_URL = 'https://files2.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip'
OUTPUT = ROOT / 'assets/models'
SOURCE_PAGE = 'https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html'


def service(module, name):
    for candidate in list(sys.modules):
        if candidate.endswith('mpfb.' + module):
            return getattr(importlib.import_module(candidate), name)
    raise RuntimeError('Enable the MPFB extension in Blender before running this generator')


def prepare_assets():
    if not (ASSETS / 'skins/young_caucasian_male/young_caucasian_male.mhmat').exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        archive = CACHE / 'system_assets_cc0.zip'
        if not archive.exists():
            subprocess.run(['curl', '--fail', '--location', '--output', str(archive), PACK_URL], check=True)
        with zipfile.ZipFile(archive) as packed:
            for name in packed.namelist():
                if Path(name).is_absolute() or '..' in Path(name).parts:
                    raise RuntimeError('Unsafe path in asset archive')
            packed.extractall(ASSETS)


def activate(obj):
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def material(name, color, roughness=.7):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    return mat


def asset_path(kind, name, extension='mhclo'):
    path = ASSETS / kind / name / (name + '.' + extension)
    if not path.is_file():
        raise RuntimeError('Missing official CC0 asset: ' + str(path))
    return path


def bake_geometry(mesh):
    activate(mesh)
    if mesh.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for modifier in list(mesh.modifiers):
        if modifier.type == 'ARMATURE':
            continue
        if modifier.type == 'SUBSURF':
            # The authored topology is sufficient at Quest viewing distances.
            mesh.modifiers.remove(modifier)
        else:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    for polygon in mesh.data.polygons:
        polygon.use_smooth = True


def aim_bone(rig, name, direction):
    retarget_kimodo.aim(rig, name, direction)
    bpy.context.view_layer.update()


def relax_and_bake_rest(rig, meshes):
    for side, sign in [('l', 1), ('r', -1)]:
        # Relaxed stance: arms hang slightly forward of the hips with a soft
        # elbow, palms turned in; the old pose tucked the hands behind the back.
        aim_bone(rig, 'upperarm_' + side, (sign * .13, -.06, -1))
        aim_bone(rig, 'lowerarm_' + side, (sign * .05, -.2, -1))
        aim_bone(rig, 'hand_' + side, (sign * .03, -.16, -1))
    for mesh in meshes:
        activate(mesh)
        for modifier in list(mesh.modifiers):
            if modifier.type == 'ARMATURE':
                bpy.ops.object.modifier_apply(modifier=modifier.name)
    activate(rig)
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    for mesh in meshes:
        modifier = mesh.modifiers.new('Humanoid skin', 'ARMATURE')
        modifier.object = rig
        modifier.use_deform_preserve_volume = False
    for bone in rig.pose.bones:
        bone.rotation_mode = 'XYZ'


def body_surface(body, x, z):
    hit, point, _normal, _face = body.ray_cast(Vector((x,-2,z)),Vector((0,1,0)))
    if hit:return point
    candidates = sorted((v.co.copy() for v in body.data.vertices if v.co.y < 0), key=lambda p: (p.x-x)**2 + (p.z-z)**2)[:4]
    result=sum(candidates,Vector())/len(candidates);result.x=x;return result


def create_shorts(body, rig):
    # Duplicate real anatomical topology, preserve skin weights and add fabric ease.
    shorts = body.copy()
    shorts.data = body.data.copy()
    shorts.name = 'PatientShorts'
    bpy.context.collection.objects.link(shorts)
    activate(shorts)
    import bmesh
    mesh = bmesh.new(); mesh.from_mesh(shorts.data)
    lower_body={g.index for g in shorts.vertex_groups if g.name in ['pelvis','spine_01','thigh_l','thigh_r']}
    allowed={v.index for v in shorts.data.vertices if sum(g.weight for g in v.groups if g.group in lower_body)>.25}
    remove = [v for v in mesh.verts if v.co.z < .62 or v.co.z > 1.055 or v.index not in allowed]
    bmesh.ops.delete(mesh, geom=remove, context='VERTS')
    mesh.to_mesh(shorts.data); mesh.free()
    shorts.data.update()
    for vertex in shorts.data.vertices:
        vertex.co += vertex.normal * .014
    shorts.data.materials.clear()
    shorts.data.materials.append(material('Patient navy training shorts', (.028, .055, .083), .9))
    solid = shorts.modifiers.new('Fabric edge thickness', 'SOLIDIFY'); solid.thickness=.003
    activate(shorts); bpy.ops.object.modifier_apply(modifier=solid.name)
    shorts.parent = rig
    return shorts


def setup_shapes(body, sternum, mouth):
    body.shape_key_add(name='Basis')
    for name in ['breathing', 'compression', 'mouth_open']:
        key = body.shape_key_add(name=name)
        for point in key.data:
            p = point.co
            if name in ['breathing', 'compression']:
                width, height = (.18,.18) if name=='breathing' else (.095,.10)
                weight = math.exp(-((p.x-sternum.x)/width)**2 - ((p.z-sternum.z)/height)**2)
                front = max(0., min(1., (-p.y - .015) / .07))
                p.y += (-.016 if name=='breathing' else .045) * weight * front
            else:
                weight = math.exp(-(p.x/.035)**2 - ((p.z-mouth.z+.008)/.027)**2)
                front = max(0., min(1., (-p.y-.04)/.05))
                if p.z < mouth.z+.002:
                    p.z -= .013 * weight * front
                    p.y -= .003 * weight * front
        key.slider_min=0.; key.slider_max=1.


def add_eye_bones(rig, eye_mesh, centres):
    """MakeHuman's game_engine rig has no eye bones, so the fitted eyeballs are
    welded to the head and cannot look anywhere. Add one deform bone per eye and
    rebind the eye mesh to them; the bone points forward (-Y) so a look-at can
    drive gaze at runtime. No authored clip keys these bones."""
    activate(rig)
    bpy.ops.object.mode_set(mode='EDIT')
    for name, centre in zip(('eye_l', 'eye_r'), centres):
        bone = rig.data.edit_bones.new(name)
        bone.head = centre
        bone.tail = centre + Vector((0, -.03, 0))
        bone.parent = rig.data.edit_bones['head']
        bone.use_deform = True
    bpy.ops.object.mode_set(mode='OBJECT')
    for group in list(eye_mesh.vertex_groups):
        eye_mesh.vertex_groups.remove(group)
    left = eye_mesh.vertex_groups.new(name='eye_l')
    right = eye_mesh.vertex_groups.new(name='eye_r')
    for vertex in eye_mesh.data.vertices:
        (left if vertex.co.x > 0 else right).add([vertex.index], 1., 'REPLACE')


def marker(name, rig, bone_name, point):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type='SPHERE'; obj.empty_display_size=.008
    bpy.context.collection.objects.link(obj)
    obj.parent=rig; obj.parent_type='BONE'; obj.parent_bone=bone_name
    bpy.context.view_layer.update()
    obj.matrix_world = Matrix.Translation(point)
    return obj


def reset_pose(rig):
    for bone in rig.pose.bones:
        bone.rotation_euler=(0,0,0)
        bone.location=(0,0,0)
        bone.scale=(1,1,1)


def key_pose(rig, frame, values):
    reset_pose(rig)
    for name, rotation in values.items():
        if name == 'pelvis_loc':
            rig.pose.bones['pelvis'].location = rotation
            continue
        rig.pose.bones[name].rotation_euler = tuple(math.radians(x) for x in rotation)
    rig.pose.bones['pelvis'].keyframe_insert('location', frame=frame, group='pelvis')
    for name in ['pelvis','spine_01','spine_02','spine_03','neck_01','head','clavicle_l','clavicle_r','upperarm_l','upperarm_r','lowerarm_l','lowerarm_r','hand_l','hand_r','thigh_l','thigh_r','calf_l','calf_r','foot_l','foot_r']:
        rig.pose.bones[name].keyframe_insert('rotation_euler', frame=frame, group=name)


def animation(rig, body, name, poses, shapes=None):
    rig.animation_data_create()
    action=bpy.data.actions.new(name)
    rig.animation_data.action=action
    for frame, pose in poses:
        key_pose(rig,frame,pose)
    slot=rig.animation_data.action_slot
    track=rig.animation_data.nla_tracks.new(); track.name=name
    strip=track.strips.new(name,1,action)
    if hasattr(strip,'action_slot') and slot:strip.action_slot=slot
    strip.action_frame_start=1; strip.action_frame_end=max(frame for frame,_ in poses)
    strip.use_animated_influence=True;strip.influence=1.;strip.extrapolation='NOTHING'
    rig.animation_data.action=None
    if shapes:
        keys=body.data.shape_keys;keys.animation_data_create()
        morph_action=bpy.data.actions.new(name + '_morphs')
        keys.animation_data.action=morph_action
        for frame, values in shapes:
            for key in keys.key_blocks:
                if key.name!='Basis':
                    key.value=values.get(key.name,0.)
                    key.keyframe_insert('value',frame=frame)
        morph_slot=keys.animation_data.action_slot
        morph_track=keys.animation_data.nla_tracks.new();morph_track.name=name
        morph_strip=morph_track.strips.new(name,1,morph_action)
        if hasattr(morph_strip,'action_slot') and morph_slot:morph_strip.action_slot=morph_slot
        morph_strip.use_animated_influence=True;morph_strip.influence=1.;morph_strip.extrapolation='NOTHING'
        keys.animation_data.action=None
    # Exporter merges NLA tracks with the same name into one glTF animation.
    for target in [rig, body.data.shape_keys]:
        if target and target.animation_data:
            for track in target.animation_data.nla_tracks:track.mute=True
    reset_pose(rig)
    for key in body.data.shape_keys.key_blocks:key.value=0.


def motion_clip(rig, body, name, tail=0., source=None, head=0.):
    """Real motion from data/motion/<source or name>.bvh (NVIDIA Kimodo), retargeted
    onto this rig as one NLA clip: the whole take, its last `tail` or first `head`
    seconds."""
    path = ROOT / 'data/motion' / ((source or name) + '.bvh')
    action, speed = retarget_kimodo.bake(rig, path, name, tail, head)
    rig.animation_data_create()
    rig.animation_data.action = action
    slot = rig.animation_data.action_slot
    track = rig.animation_data.nla_tracks.new(); track.name = name
    strip = track.strips.new(name, 1, action)
    if hasattr(strip, 'action_slot') and slot: strip.action_slot = slot
    strip.extrapolation = 'NOTHING'
    rig.animation_data.action = None
    for track in rig.animation_data.nla_tracks: track.mute = True
    reset_pose(rig)
    print('NARET_KIMODO', name, 'frames', int(action.frame_range[1]), 'speed %.2f m/s' % speed, flush=True)
    return speed


def create_animations(rig, body, patient):
    if patient:
        animation(rig,body,'idle',[(1,{}),(61,{})],[(1,{}),(61,{})])
        animation(rig,body,'breathing',[(1,{}),(49,{}),(97,{})],[(1,{}),(37,{'breathing':1.}),(61,{'breathing':.35}),(97,{})])
        animation(rig,body,'compression',[(1,{}),(9,{}),(17,{})],[(1,{}),(9,{'compression':1.}),(17,{})])
    else:
        # NVIDIA Kimodo takes (data/motion). Marek kneels down and takes over
        # compressions while the pads go on (ERC 2025): one sequenced take, its
        # start as `kneel`, its end looping as `cpr`.
        for name in ('idle', 'talk', 'anxious', 'phone', 'walk', 'relief'):
            motion_clip(rig, body, name)
        motion_clip(rig, body, 'reach', 1.6)
        motion_clip(rig, body, 'kneel', source='cpr', head=1.9)
        motion_clip(rig, body, 'cpr', 3.0)

def simplify_materials():
    # Standard Principled textures export without MPFB's procedural shader groups.
    for mat in bpy.data.materials:
        if not mat.use_nodes:continue
        bsdf=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
        if bsdf:
            bsdf.inputs['Metallic'].default_value=0
            bsdf.inputs['Roughness'].default_value=.67
            if 'Emission Strength' in bsdf.inputs:bsdf.inputs['Emission Strength'].default_value=0
        mat.use_backface_culling=False
    for image in bpy.data.images:
        if image.source=='FILE' and image.size[0]>0:
            limit=2048 if ('skin' in image.name or 'diffuse' in image.name and 'lightskin' in image.name) else 1024
            if max(image.size)>limit:
                factor=limit/max(image.size);image.scale(int(image.size[0]*factor),int(image.size[1]*factor))
            image.pack()


def normalize_gltf(path):
    """Join Blender action slots and enforce correct game-engine alpha modes.

    MPFB's GAMEENGINE shader links alpha on all materials. Godot must treat skin
    as opaque to avoid transparent-triangle sorting artifacts. Blender 5.2's
    NLA_TRACKS mode loses animated slots; ACTIONS exports them correctly, and
    this joins each explicitly named skeleton/morph action pair losslessly.
    """
    raw=path.read_bytes();json_length=struct.unpack_from('<I',raw,12)[0]
    data=json.loads(raw[20:20+json_length]);remaining=raw[20+json_length:]
    for mat in data.get('materials',[]):
        name=mat.get('name','').lower()
        cutout=any(token in name for token in ['eyebrow','eyelash','short01','bob02','ponytail01'])
        if cutout:
            mat['alphaMode']='MASK';mat['alphaCutoff']=.4;mat['doubleSided']=True
        else:
            mat.pop('alphaMode',None);mat.pop('alphaCutoff',None);mat['doubleSided']=False
        # Skin has a soft sheen, eyes are wet, cloth is matte, hair in between.
        pbr=mat.setdefault('pbrMetallicRoughness',{});pbr['metallicFactor']=0.
        for token,rough in [('.body',.5),('low-poly',.08),('teeth',.3),('eyebrow',.8),('eyelash',.8),('short01',.62),('ponytail01',.62),('casualsuit',.88),('shoes',.55),('shirt',.85),('shorts',.85)]:
            if token in name:pbr['roughnessFactor']=rough;break
    animations={anim['name']:anim for anim in data.get('animations',[]) if not anim['name'].endswith('_morphs')}
    for anim in data.get('animations',[]):
        if not anim['name'].endswith('_morphs'):continue
        name=anim['name'].removesuffix('_morphs')
        target=animations.setdefault(name,{'name':name,'channels':[],'samplers':[]})
        offset=len(target['samplers']);target['samplers'].extend(anim['samplers'])
        for channel in anim['channels']:
            channel['sampler']+=offset;target['channels'].append(channel)
    data['animations']=list(animations.values())
    for mesh in data.get('meshes',[]):
        if 'weights' in mesh:mesh['weights']=[0.]*len(mesh['weights'])
    encoded=json.dumps(data,separators=(',',':')).encode()
    encoded+=b' '*((-len(encoded))%4)
    total=12+8+len(encoded)+len(remaining)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,total)+struct.pack('<I4s',len(encoded),b'JSON')+encoded+remaining)


def make_character(name, gender, patient=False):
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for action in list(bpy.data.actions):bpy.data.actions.remove(action)
    H=service('services.humanservice','HumanService')
    T=service('services.targetservice','TargetService')
    macro=T.get_default_macro_info_dict()
    macro.update(gender=gender,age=.57 if patient else .42,muscle=.57 if patient else .45,weight=.48,height=.48 if patient else .42)
    macro['race']={'caucasian':1.,'african':0.,'asian':0.}
    body=H.create_human(macro_detail_dict=macro)
    body.name='PatientBody' if patient else 'BystanderBody'
    rig=H.add_builtin_rig(body,'game_engine');rig.name='HumanRig'
    skin_name='middleage_caucasian_male' if patient else ('young_caucasian_female' if gender<.5 else 'young_caucasian_male')
    H.set_character_skin(str(asset_path('skins',skin_name,'mhmat')),body,skin_type='GAMEENGINE')
    assets=[('eyes','low-poly','Eyes'),('eyebrows','eyebrow001','Eyebrows'),('eyelashes','eyelashes01','Eyelashes'),('teeth','teeth_base','Teeth'),('hair','short01' if gender>.5 else 'ponytail01','Hair')]
    if not patient:
        assets.extend([('clothes','female_casualsuit01' if gender<.5 else 'male_casualsuit04','Clothes'),('clothes','shoes01','Clothes')])
    loaded=[]
    for kind,asset,typ in assets:
        obj=H.add_mhclo_asset(str(asset_path(kind,asset)),body,asset_type=typ,subdiv_levels=0,material_type='GAMEENGINE')
        if obj:loaded.append(obj)
    meshes=[obj for obj in bpy.context.scene.objects if obj.type=='MESH']
    for mesh in meshes:bake_geometry(mesh)
    relax_and_bake_rest(rig,meshes)
    if patient:
        meshes.append(create_shorts(body,rig))
    else:
        cloth=next(obj for obj in meshes if 'casualsuit' in obj.name)
        shirt=material('NaReT everyday shirt',(.19,.023,.041) if gender<.5 else (.105,.144,.068))  # burgundy / olive, sRGB #7a2a3a / #5b6a4a
        cloth.data.materials.append(shirt)
        slot=len(cloth.data.materials)-1
        adjacency=[set() for _ in cloth.data.vertices]
        for edge in cloth.data.edges:
            a,b=edge.vertices;adjacency[a].add(b);adjacency[b].add(a)
        shirt_vertices=set();visited=set()
        for vertex in cloth.data.vertices:
            if vertex.index in visited:continue
            component=set();pending=[vertex.index]
            while pending:
                index=pending.pop()
                if index in component:continue
                component.add(index);pending.extend(adjacency[index]-component)
            visited.update(component)
            if max(cloth.data.vertices[i].co.z for i in component)>rig.data.bones['clavicle_l'].head_local.z-.13:shirt_vertices.update(component)
        for face in cloth.data.polygons:
            if any(i in shirt_vertices for i in face.vertices):face.material_index=slot
    # Keep only the actual deform groups; helpers never enter a GLB.
    for mesh in meshes:
        for group in list(mesh.vertex_groups):
            if group.name not in rig.data.bones:mesh.vertex_groups.remove(group)
    # CPR compression point (ERC 2025: centre of the chest = lower half of the
    # sternum, about the nipple line). +.075 sat at the xiphoid, 5 cm too low.
    sternum=body_surface(body,0,rig.data.bones['spine_03'].head_local.z+.125)
    mouth=body_surface(body,0,rig.data.bones['head'].head_local.z-.008)
    forehead=body_surface(body,0,rig.data.bones['head'].head_local.z+.082)
    eye_z=rig.data.bones['head'].head_local.z+.051
    eye_mesh=next(obj for obj in meshes if 'low-poly' in obj.name)
    eyes=[];centres=[]
    for sign in [1,-1]:
        points=[v.co.copy() for v in eye_mesh.data.vertices if v.co.x*sign>0]
        centre=sum(points,Vector())/len(points)
        centres.append(centre.copy())
        # The marker sits on the front surface; the bone pivots at the ball centre.
        front=centre.copy();front.y=min(v.y for v in points);eyes.append(front)
    add_eye_bones(rig,eye_mesh,centres)
    setup_shapes(body,sternum,mouth)
    markers=[marker('Sternum',rig,'spine_03',sternum),marker('Mouth',rig,'head',mouth),marker('Forehead',rig,'head',forehead),marker('EyeLeft',rig,'eye_l',eyes[0]),marker('EyeRight',rig,'eye_r',eyes[1])]
    desired_height=1.76 if patient else (1.70 if gender<.5 else 1.78)
    # Clothing delete-groups cut the covered body geometry away, so a body-only
    # bound measures bare hips, not feet. Size the whole silhouette instead.
    extent=[v.co.z for mesh in meshes for v in mesh.data.vertices]
    bottom=min(extent)
    body_height=max(extent)-bottom
    scale=desired_height/body_height
    rig.scale=(scale,scale,scale)
    rig.location.z=-bottom*scale
    if patient:
        rig.rotation_euler.x=-math.pi/2
        # Supine clinical origin: lower sternum at local z=-0.08 after GLTF conversion.
        rig.location.y=.08-sternum.z*scale
        back=max(v.co.y for v in body.data.vertices if .95<v.co.z<1.5)
        rig.location.z=back*scale+.005
    create_animations(rig,body,patient)
    simplify_materials()
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    chosen=[rig]+meshes+markers
    bpy.ops.object.select_all(action='DESELECT')
    for obj in chosen:obj.select_set(True)
    bpy.context.view_layer.objects.active=rig
    rig['source']='MakeHuman Community / MPFB';rig['asset_license']='CC0-1.0'
    rig['clinical_pose']='supine, head -Z' if patient else 'upright, forward +Z'
    output=OUTPUT/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',use_selection=True,export_apply=False,export_animations=True,export_animation_mode='ACTIONS',export_merge_animation='NONE',export_force_sampling=True,export_morph=True,export_skins=True,export_def_bones=True,export_yup=True,export_extras=True,export_image_format='AUTO')
    normalize_gltf(output)
    points={o.name:[round(o.matrix_world.translation.x,5),round(o.matrix_world.translation.z,5),round(-o.matrix_world.translation.y,5)] for o in markers}
    info={'file':output.name,'source':SOURCE_PAGE,'license':'CC0-1.0','adult_height_m':desired_height,'skin':skin_name,'assets':[x[1] for x in assets],'rig':'MakeHuman game_engine','bones':[bone.name for bone in rig.data.bones],'markers_godot':points,'blend_shapes':['breathing','compression','mouth_open'],'triangles':sum(sum(len(p.vertices)-2 for p in m.data.polygons) for m in meshes),'mesh_count':len(meshes),'file_bytes':output.stat().st_size,'sha256':hashlib.sha256(output.read_bytes()).hexdigest()}
    CACHE.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(CACHE/(name+'.blend')))
    source_dir=ROOT/'build/source';source_dir.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(CACHE/(name+'.blend'),source_dir/(name+'.blend'))
    render_preview(name,patient)
    return info


def render_preview(name,patient):
    scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.samples=32
    scene.render.resolution_x=1100;scene.render.resolution_y=850;scene.render.resolution_percentage=100
    scene.world.color=(.13,.13,.13)
    scene.view_settings.view_transform='AgX'
    scene.view_settings.exposure=-.45
    floor=material('Studio ground',(.038,.05,.065))
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.01));bpy.context.object.data.materials.append(floor)
    target=Vector((0,-.35,.13) if patient else (0,0,.94))
    bpy.ops.object.camera_add(location=(2.1,-2.9,2.35) if patient else (2.45,-4.2,1.75))
    cam=bpy.context.object;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.2 if patient else 2.6;scene.camera=cam
    for loc,power,size in [((3,-4,5),750,4),((-3,-1,3),550,3),((0,3,4),850,2.5)]:
        bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(CACHE/(name+'_preview.png'))
    bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only',choices=['patient','female','male'])
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if not any(m.endswith('mpfb.services.humanservice') for m in sys.modules):bpy.ops.preferences.addon_enable(module='bl_ext.blender_org.mpfb')
    prepare_assets();OUTPUT.mkdir(parents=True,exist_ok=True)
    specs=[('human_patient',1.,True,'patient'),('human_bystander',.08,False,'female'),('human_bystander_male',.95,False,'male')]
    reports=[]
    for name,gender,patient,key in specs:
        if args.only is None or args.only==key:
            print('NARET_BUILD_HUMAN',name,flush=True)
            reports.append(make_character(name,gender,patient))
    path=OUTPUT/'human_models.json'
    old=json.loads(path.read_text()) if path.exists() else []
    if args.only:reports=[x for x in old if x['file'] not in [r['file'] for r in reports]]+reports
    path.write_text(json.dumps(reports,indent=2)+'\n')
    print('NARET_HUMANS_DONE',[(r['file'],r['triangles']) for r in reports],flush=True)

if __name__=='__main__':main()
