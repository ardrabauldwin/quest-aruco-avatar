#!/usr/bin/env python3
"""Add closed eyes and face injuries to the existing patient model, nothing else.

17 Nov 2026: "add [to the] old patient [the] injuries, closed eyes (they open on return
of circulation), only these changes". Ported from the team's sensor-log branch
(Dennis, tools/generate_humans.py: add_eyes_closed, sink_eyes, paint_injuries), which
does this in Blender while generating a new, clothed, lying patient. Here the same
steps run directly on this project's model file, so its body, pose, fit to the Little
Anne torso (node PatientFitLittleAnne) and everything else stay as they are.

  * shape key "eyes_closed" on the body and the eyelashes (the upper lid swings down
    over the eye) and on the eyes (2.5 mm deeper, a little smaller), weight 0;
    the app sets it to 1 while unconscious (NaretMannequin).
  * painted into the skin texture: a graze with a cut above the right brow and a
    bruise on the left cheekbone. NOT Dennis's bluish lips (cyanosis).

  python tools/add_patient_eyes_injuries.py SOURCE.glb TARGET.glb

Coordinates: Dennis's formulas use a standing character in Blender axes: x = the
character's left, -y = the way the face looks, z = up towards the crown. This model's
mesh lies on its back (face +Y, crown -Z, left +X, checked on the bones 17 Nov 2026),
so his frame is (x, -y, -z) of the mesh: a half turn about x, its own inverse.
"""
import io
import json
import math
import struct
import sys

import numpy as np
from PIL import Image

INJURIES = [
    # (x, z offset from the head bone, length, width, tilt deg, colour 0-1, strength, kind)
    # Dennis's values; character's left is +X, metres. His fourth row (bluish lips) is left out.
    (-.030, .070, .030, .026, 0, (.48, .16, .12), .75, 'graze'),  # abrasion above the right brow
    (-.030, .070, .022, .0035, -20, (.28, .02, .02), .95, 'cut'),  # laceration in it
    (.048, .032, .026, .022, 0, (.30, .17, .30), .55, 'bruise'),  # bruised left cheekbone
]
COMPONENT = {5126: ('f', 4), 5125: ('I', 4), 5123: ('H', 2), 5121: ('B', 1)}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


class Glb:
    def __init__(self, path):
        data = open(path, 'rb').read()
        json_len = struct.unpack_from('<I', data, 12)[0]
        self.json = json.loads(data[20:20 + json_len])
        bin_start = 20 + json_len + 8
        self.bin = data[bin_start:bin_start + struct.unpack_from('<I', data, 20 + json_len)[0]]
        self.views = [self.bin[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']] for v in self.json['bufferViews']]

    def read(self, index):
        a = self.json['accessors'][index]
        fmt, size = COMPONENT[a['componentType']]
        width = WIDTH[a['type']]
        view = self.json['bufferViews'][a['bufferView']]
        stride = view.get('byteStride', size * width)
        raw = self.views[a['bufferView']]
        out = np.empty((a['count'], width), dtype=np.float64)
        for i in range(a['count']):
            out[i] = struct.unpack_from('<%d%s' % (width, fmt), raw, a.get('byteOffset', 0) + i * stride)
        return out

    def add_vec3(self, values):
        values = np.asarray(values, dtype=np.float32)
        self.views.append(values.tobytes())
        self.json['bufferViews'].append({'buffer': 0, 'byteLength': len(self.views[-1])})
        self.json['accessors'].append({'bufferView': len(self.views) - 1, 'componentType': 5126, 'count': len(values),
                                       'type': 'VEC3', 'min': values.min(0).tolist(), 'max': values.max(0).tolist()})
        return len(self.json['accessors']) - 1

    def save(self, path):
        blob = bytearray()
        for i, data in enumerate(self.views):
            while len(blob) % 4:
                blob.append(0)
            self.json['bufferViews'][i]['byteOffset'] = len(blob)
            self.json['bufferViews'][i]['byteLength'] = len(data)
            blob += data
        while len(blob) % 4:
            blob.append(0)
        self.json['buffers'][0]['byteLength'] = len(blob)
        text = json.dumps(self.json, separators=(',', ':')).encode()
        text += b' ' * (-len(text) % 4)
        with open(path, 'wb') as out:
            out.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(text) + 8 + len(blob)))
            out.write(struct.pack('<II', len(text), 0x4E4F534A) + text)
            out.write(struct.pack('<II', len(blob), 0x004E4942) + bytes(blob))


def to_blender(p):
    """Mesh (lying) to Dennis's standing frame; see the module note."""
    return np.column_stack([p[:, 0], -p[:, 1], -p[:, 2]])


def from_blender(p):
    return to_blender(p)


def mesh_named(glb, suffix):
    for i, mesh in enumerate(glb.json['meshes']):
        if mesh['name'] == suffix:
            return i, mesh
    raise SystemExit('mesh %s missing' % suffix)


def widen_weight_animations(glb, mesh_index):
    """Animations that drive this mesh's morph weights store one value per target and
    keyframe. Give the new target a 0 in each, so the old values keep their meaning."""
    nodes = [i for i, node in enumerate(glb.json['nodes']) if node.get('mesh') == mesh_index]
    targets = len(glb.json['meshes'][mesh_index]['primitives'][0]['targets'])
    for animation in glb.json.get('animations', []):
        for channel in animation['channels']:
            if channel['target']['path'] != 'weights' or channel['target'].get('node') not in nodes:
                continue
            sampler = animation['samplers'][channel['sampler']]
            keys = glb.json['accessors'][sampler['input']]['count']
            per_key = 3 if sampler.get('interpolation') == 'CUBICSPLINE' else 1
            old = glb.read(sampler['output']).reshape(keys * per_key, -1)
            if old.shape[1] != targets - 1:
                raise SystemExit('animation %s: %d weights per key, expected %d' % (animation.get('name'), old.shape[1], targets - 1))
            new = np.hstack([old, np.zeros((len(old), 1))]).astype(np.float32).reshape(-1)
            glb.views.append(new.tobytes())
            glb.json['bufferViews'].append({'buffer': 0, 'byteLength': len(glb.views[-1])})
            glb.json['accessors'].append({'bufferView': len(glb.views) - 1, 'componentType': 5126, 'count': len(new), 'type': 'SCALAR'})
            sampler['output'] = len(glb.json['accessors']) - 1
            print('animation %s: weights widened to %d per key' % (animation.get('name'), targets))


def add_target(glb, mesh, name, deltas_gltf):
    prim = mesh['primitives'][0]
    target = {'POSITION': glb.add_vec3(deltas_gltf)}
    # Keep every target's attribute set alike (some importers expect it).
    for other in prim.get('targets', []):
        for attr in other:
            if attr != 'POSITION' and attr not in target:
                target[attr] = glb.add_vec3(np.zeros_like(deltas_gltf))
    prim.setdefault('targets', []).append(target)
    mesh.setdefault('extras', {}).setdefault('targetNames', []).append(name)
    mesh['weights'] = mesh.get('weights', [0.0] * (len(prim['targets']) - 1)) + [0.0]
    widen_weight_animations(glb, glb.json['meshes'].index(mesh))


def lids_closed(points, centres, radius, lashes):
    """Dennis's add_eyes_closed on Blender-axis points: the closed positions."""
    out = points.copy()
    for k, p in enumerate(points):
        for c in centres:
            d = p - c
            if d[1] > 0 or abs(d[0]) > .021:
                continue
            dist = math.hypot(d[1], d[2])
            phi = math.degrees(math.atan2(d[2], -d[1]))
            if phi < 0 or (not lashes and abs(dist - radius) > .009):
                continue
            lateral = max(0., 1 - (d[0] / .020) ** 4)
            upward = min(1., max(0., (35 - phi) / 20))
            radial = 1. if lashes else min(1., max(0., (.009 - abs(dist - radius)) / .004))
            outer = max(0., min(1., d[0] * math.copysign(1, c[0]) / .012))
            turn = math.radians((47 + 14 * outer) * lateral * upward * radial)
            if turn == 0:
                continue
            new = math.atan2(d[2], -d[1]) - turn
            out[k][1] = c[1] - dist * math.cos(new)
            out[k][2] = c[2] + dist * math.sin(new)
    return out


def head_bone_z(glb):
    """The head bone's height in Dennis's frame (-z of the mesh), from the skin's inverse bind matrix."""
    skin = glb.json['skins'][0]
    names = [glb.json['nodes'][j].get('name') for j in skin['joints']]
    ibm = glb.read(skin['inverseBindMatrices'])[names.index('head')].reshape(4, 4).T
    return float(-np.linalg.inv(ibm)[2, 3])


def paint_injuries(glb, body_mesh, head_z):
    prim = body_mesh['primitives'][0]
    pos = to_blender(glb.read(prim['attributes']['POSITION']))
    uv = glb.read(prim['attributes']['TEXCOORD_0'])
    tris = glb.read(prim['indices']).astype(int).reshape(-1, 3)
    material = glb.json['materials'][prim['material']]
    image_index = glb.json['textures'][material['pbrMetallicRoughness']['baseColorTexture']['index']]['source']
    image_json = glb.json['images'][image_index]
    image = Image.open(io.BytesIO(glb.views[image_json['bufferView']])).convert('RGBA')
    w, h = image.size
    px = np.asarray(image, dtype=np.float32) / 255.0
    # Front faces only, near the face: a ray from the front along +Y (Blender).
    front = tris[(pos[tris][:, :, 1].mean(1) < 0)]
    rng = np.random.default_rng(3)

    def pixel(x, z):
        best, best_y = None, math.inf
        for t in front:
            a, b, c = pos[t][:, [0, 2]]
            m = np.array([[b[0] - a[0], c[0] - a[0]], [b[1] - a[1], c[1] - a[1]]])
            if abs(np.linalg.det(m)) < 1e-12:
                continue
            s, r = np.linalg.solve(m, np.array([x - a[0], z - a[1]]))
            if s < -1e-9 or r < -1e-9 or s + r > 1 + 1e-9:
                continue
            y = pos[t[0]][1] * (1 - s - r) + pos[t[1]][1] * s + pos[t[2]][1] * r
            if y < best_y:
                best_y, best = y, (t, s, r)
        if best is None:
            raise SystemExit('no skin at x=%.3f z=%.3f' % (x, z))
        t, s, r = best
        q = uv[t[0]] * (1 - s - r) + uv[t[1]] * s + uv[t[2]] * r
        return np.array([q[0] * w, q[1] * h])

    # Faces in the head region only, to keep the search short.
    near = np.abs(pos[front][:, :, 2].mean(1) - head_z - .05) < .2
    front = front[near]
    e = .005
    for x, dz, length, width, tilt, colour, strength, kind in INJURIES:
        z = head_z + dz
        centre = pixel(x, z)
        jac = np.column_stack([(pixel(x + e, z) - pixel(x - e, z)) / (2 * e), (pixel(x, z + e) - pixel(x, z - e)) / (2 * e)])
        to_metres = np.linalg.inv(jac)
        reach = max(length, width) * np.linalg.norm(jac, 2)
        x0, x1 = int(max(centre[0] - reach, 0)), int(min(centre[0] + reach, w))
        y0, y1 = int(max(centre[1] - reach, 0)), int(min(centre[1] + reach, h))
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        local = np.einsum('ij,jyx->iyx', to_metres, np.stack([xx - centre[0], yy - centre[1]]))
        cs, sn = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
        along = (cs * local[0] + sn * local[1]) / (length / 2)
        across = (-sn * local[0] + cs * local[1]) / (width / 2)
        alpha = np.exp(-(along ** 2 + across ** 2) * 2)
        if kind == 'cut':
            alpha = np.exp(-along ** 8 - across ** 2 * 2)
        if kind == 'graze':
            alpha *= rng.random(alpha.shape) * .6 + .4
        alpha = (alpha * strength)[..., None]
        px[y0:y1, x0:x1, :3] = px[y0:y1, x0:x1, :3] * (1 - alpha) + np.array(colour) * alpha
        print('painted %s at pixel (%d, %d), %d px across' % (kind, centre[0], centre[1], reach))
    out = io.BytesIO()
    Image.fromarray(np.clip(px * 255 + .5, 0, 255).astype(np.uint8)).save(out, 'PNG', optimize=True)
    glb.views[image_json['bufferView']] = out.getvalue()


def main():
    source, target = sys.argv[1], sys.argv[2]
    glb = Glb(source)
    for mesh in glb.json['meshes']:
        if 'eyes_closed' in mesh.get('extras', {}).get('targetNames', []):
            raise SystemExit('%s already has eyes_closed' % mesh['name'])
    _, eyes = mesh_named(glb, 'low-poly')
    eye_points = to_blender(glb.read(eyes['primitives'][0]['attributes']['POSITION']))
    centres = [eye_points[eye_points[:, 0] > 0].mean(0), eye_points[eye_points[:, 0] < 0].mean(0)]
    radius = float(np.linalg.norm(eye_points[eye_points[:, 0] > 0] - centres[0], axis=1).mean())
    print('eye centres', [c.round(4).tolist() for c in centres], 'radius %.4f' % radius)
    for name, lashes in (('base', False), ('eyelashes01', True)):
        _, mesh = mesh_named(glb, name)
        points = to_blender(glb.read(mesh['primitives'][0]['attributes']['POSITION']))
        closed = lids_closed(points, centres, radius, lashes)
        moved = int((np.abs(closed - points).sum(1) > 1e-7).sum())
        print('%s: %d vertices close the lid' % (name, moved))
        add_target(glb, mesh, 'eyes_closed', from_blender(closed) - from_blender(points))
    sunk = []
    for p in eye_points:
        c = min(centres, key=lambda q: np.linalg.norm(p - q))
        sunk.append(c + (p - c) * .9 + np.array([0, .0025, 0]))
    add_target(glb, eyes, 'eyes_closed', from_blender(np.array(sunk)) - from_blender(eye_points))
    _, body = mesh_named(glb, 'base')
    paint_injuries(glb, body, head_bone_z(glb))
    glb.save(target)
    print('wrote', target)


if __name__ == '__main__':
    main()
