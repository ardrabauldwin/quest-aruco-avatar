#!/usr/bin/env python3
"""Bake the Little Anne fit into the patient model file (15 Nov 2026).

The avatar's head and torso are sized to the Laerdal Little Anne QCPR torso: 65 cm from
the crown to the hips, 34 cm at the widest point (Laerdal's published size), measured as
the app's former runtime fit did (MannequinController._fit_patient: head and trunk only,
arms and legs left out). Relative to the patient scene's own uniform 0.9 that is

  across the body (X)  1.0571110
  along the body  (Z)  0.8971521
  height          (Y)  1.0 (the chest fit, set_thickness, owns the height)

The factors go onto a new top node of the glTF scene, "PatientFitLittleAnne", whose
child is the unchanged rig. The skeleton, its skin and the animations inside are not
touched, so breathing, head tilt and the arm movement keep working; the whole rig is
simply drawn stretched, as it was by the runtime fit.

Always starts from the original, kept in build/model_backup/ (created on the first run),
so running this again never stretches the model twice. To undo, copy that file back.
tools/generate_humans.py makes the original; run this after regenerating it.

  python tools/fit_patient_glb.py
"""
import json
import shutil
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / 'assets/models/human_patient.glb'
BACKUP = ROOT / 'build/model_backup/human_patient_original.glb'
FIT_NODE = 'PatientFitLittleAnne'
SCALE = [1.0571110, 1.0, 0.8971521]


def read_glb(path):
    data = path.read_bytes()
    magic, version, _length = struct.unpack('<III', data[:12])
    assert magic == 0x46546C67 and version == 2, 'not a glTF 2 binary'
    offset = 12
    chunks = []
    while offset < len(data):
        size, kind = struct.unpack('<II', data[offset:offset + 8])
        chunks.append((kind, data[offset + 8:offset + 8 + size]))
        offset += 8 + size
    assert chunks[0][0] == 0x4E4F534A, 'first chunk is not JSON'
    return json.loads(chunks[0][1]), chunks[1:]


def write_glb(path, document, rest):
    text = json.dumps(document, separators=(',', ':')).encode('utf-8')
    text += b' ' * ((4 - len(text) % 4) % 4)
    body = struct.pack('<II', len(text), 0x4E4F534A) + text
    for kind, payload in rest:
        payload += b'\0' * ((4 - len(payload) % 4) % 4)
        body += struct.pack('<II', len(payload), kind) + payload
    path.write_bytes(struct.pack('<III', 0x46546C67, 2, 12 + len(body)) + body)


def main():
    if not BACKUP.exists():
        BACKUP.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(MODEL, BACKUP)
        print('original kept as', BACKUP.relative_to(ROOT))
    document, rest = read_glb(BACKUP)
    names = [node.get('name') for node in document['nodes']]
    assert FIT_NODE not in names, 'the backup is already fitted; restore the real original first'
    scene = document['scenes'][document.get('scene', 0)]
    document['nodes'].append({'name': FIT_NODE, 'scale': SCALE, 'children': list(scene['nodes'])})
    scene['nodes'] = [len(document['nodes']) - 1]
    write_glb(MODEL, document, rest)
    print('written', MODEL.relative_to(ROOT), 'with', FIT_NODE, 'scale', SCALE)


if __name__ == '__main__':
    main()
