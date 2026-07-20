import trimesh
import numpy as np
from pathlib import Path

p = Path(r'c:/Users/bauld/gdextension_test/project/assets/avatar/mannequin.glb')
mesh = trimesh.load(p)
print('type', type(mesh).__name__)
if isinstance(mesh, trimesh.Scene):
    print('scene geometry', list(mesh.geometry.keys()))
    for name, geom in mesh.geometry.items():
        print('geom', name, type(geom).__name__)
        if hasattr(geom, 'bounds'):
            print(' bounds', geom.bounds)
            print(' extents', geom.extents)
            print(' centroid', geom.centroid)
        if hasattr(geom, 'vertices'):
            print(' vertices', len(geom.vertices), 'faces', len(geom.faces))
elif isinstance(mesh, trimesh.Trimesh):
    print('bounds', mesh.bounds)
    print('extents', mesh.extents)
    print('centroid', mesh.centroid)
    print('vertices', len(mesh.vertices), 'faces', len(mesh.faces))
else:
    print(mesh)
