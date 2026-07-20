from pygltflib import GLTF2
import numpy as np
from pathlib import Path

p = Path(r'c:/Users/bauld/gdextension_test/project/assets/avatar/mannequin.glb')
glb = GLTF2().load(str(p))
print('file', p)
print('nodes', len(glb.nodes))
print('meshes', len(glb.meshes))
print('scenes', len(glb.scenes))
for i, n in enumerate(glb.nodes):
    print('node', i, getattr(n, 'name', None), 'children', getattr(n, 'children', None))

mesh = glb.meshes[0]
prim = mesh.primitives[0]
print('mesh name', mesh.name)
print('primitive', prim)
print('attributes', list(prim.attributes.keys()))

# Try to print mesh positions if available from glb buffers
for attr_name in prim.attributes:
    print('attr', attr_name, 'type', type(prim.attributes[attr_name]).__name__)
    # Access underlying indices? not necessary

# inspect accessor counts from glb data
for key, accessor_idx in prim.attributes.items():
    acc = glb.accessors[accessor_idx]
    print('accessor', key, 'count', acc.count, 'component_type', acc.component_type, 'type', acc.type)
