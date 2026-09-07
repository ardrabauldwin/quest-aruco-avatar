"""Render the actual GLB surface and texture for reviewing the prototype CPR target.

Run from the repository root. Uses numpy and Pillow; no anatomical inference is automated.
"""
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

with open('project/assets/avatar/mannequin.glb', 'rb') as f:
    f.read(12)
    size, _ = struct.unpack('<II', f.read(8))
    model = json.loads(f.read(size))
    size, _ = struct.unpack('<II', f.read(8))
    binary = f.read(size)

def accessor(index):
    a = model['accessors'][index]
    v = model['bufferViews'][a['bufferView']]
    dtype = {5126: '<f4', 5123: '<u2'}[a['componentType']]
    width = {'VEC3': 3, 'VEC2': 2, 'SCALAR': 1}[a['type']]
    return np.ndarray((a['count'], width), dtype=dtype, buffer=binary,
                      offset=v.get('byteOffset', 0) + a.get('byteOffset', 0),
                      strides=(v.get('byteStride', np.dtype(dtype).itemsize * width),
                               np.dtype(dtype).itemsize)).copy()

def rotate(points, quaternion):
    q = np.asarray(quaternion, dtype=float)
    q /= np.linalg.norm(q)
    return points + 2 * np.cross(q[:3], np.cross(q[:3], points) + q[3] * points)

points, normals, uv = accessor(0), accessor(1), accessor(2)
for index in (0, 5):
    points = rotate(points, model['nodes'][index]['rotation'])
    normals = rotate(normals, model['nodes'][index]['rotation'])
triangles = accessor(3).reshape(-1, 3)
view = model['bufferViews'][model['images'][0]['bufferView']]
texture = np.asarray(Image.open(io.BytesIO(binary[view['byteOffset']:view['byteOffset'] + view['byteLength']])).convert('RGB'))

# Front view: head at top (-Z), +Y toward camera. Pixel mapping stays in model coordinates.
width, height, scale = 800, 1100, 1150
screen = np.column_stack((400 + points[:, 0] * scale, 520 + points[:, 2] * scale))
depth = np.full((height, width), -np.inf)
pixels = np.full((height, width, 3), 242, dtype=np.uint8)
for ids in triangles:
    p = screen[ids]
    lo = np.maximum(np.floor(p.min(axis=0)).astype(int), 0)
    hi = np.minimum(np.ceil(p.max(axis=0)).astype(int), [width - 1, height - 1])
    if np.any(hi < lo):
        continue
    xx, yy = np.meshgrid(np.arange(lo[0], hi[0] + 1), np.arange(lo[1], hi[1] + 1))
    a, b, c = p
    det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(det) < 1e-9:
        continue
    w0 = ((b[1] - c[1]) * (xx - c[0]) + (c[0] - b[0]) * (yy - c[1])) / det
    w1 = ((c[1] - a[1]) * (xx - c[0]) + (a[0] - c[0]) * (yy - c[1])) / det
    weights = np.stack((w0, w1, 1 - w0 - w1), axis=-1)
    z = weights @ points[ids, 1]
    mask = (weights.min(axis=-1) >= -1e-6) & (z > depth[yy, xx])
    if not mask.any():
        continue
    tex = weights[mask] @ uv[ids]
    tx = np.clip((tex[:, 0] * (texture.shape[1] - 1)).astype(int), 0, texture.shape[1] - 1)
    ty = np.clip((tex[:, 1] * (texture.shape[0] - 1)).astype(int), 0, texture.shape[0] - 1)
    light = np.clip(0.45 + 0.55 * (weights[mask] @ normals[ids, 1]), 0.2, 1)
    pixels[yy[mask], xx[mask]] = (texture[ty, tx] * light[:, None]).astype(np.uint8)
    depth[yy[mask], xx[mask]] = z[mask]

image = Image.fromarray(pixels)
draw = ImageDraw.Draw(image)
draw.text((20, 20), 'Actual avatar mesh: front view; head above, abdomen below', fill='black')
for z in np.arange(-0.3, 0.4, 0.05):
    y = 520 + z * scale
    draw.text((15, y), f'Z {z:+.2f}', fill='black')
    draw.line((90, y, 110, y), fill='black')
draw.line((400, 480, 400, 920), fill=(50, 130, 200), width=1)
# Both footprints use the retained centre Z=0.12. This is a review annotation,
# not a medical segmentation or a runtime screenshot.
for half_x, half_z, color in ((0.065, 0.065, (230, 130, 0)), (0.04, 0.035, (0, 160, 80))):
    draw.rectangle((400 - half_x * scale, 520 + (0.12 - half_z) * scale,
                    400 + half_x * scale, 520 + (0.12 + half_z) * scale),
                   outline=color, width=3)
draw.text((20, 1010), 'Orange: previous footprint. Green: refined prototype footprint.', fill='black')
draw.text((20, 1030), 'Model-based estimate; sternum/xiphoid boundaries are not labelled in this mesh.', fill='black')
Path('builds').mkdir(exist_ok=True)
image.save('builds/cpr_target_model_front.png')
for z in (0.10, 0.12, 0.15, 0.18, 0.20):
    sample = points[(abs(points[:, 0]) < 0.015) & (abs(points[:, 2] - z) < 0.005), 1]
    print(f'centreline Z={z:.3f}, surface Y median={np.median(sample):.5f}')
