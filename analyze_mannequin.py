"""
Work out where ArUco markers can actually go on mannequin.glb.

    pip install trimesh numpy scipy
    python analyze_mannequin.py

Four steps:
  1. PCA           -> find the body's own axes (the mesh is authored tilted ~37 deg)
  2. Width profile -> label head / neck / shoulders / chest, purely from the shape
  3. Flatness      -> for a given marker size, the GAP that opens under a rigid flat marker
  4. Convert       -> best spots, in the coordinates Godot's `mannequin` node uses

The flatness number is the whole point. A marker is a rigid flat square; skin is curved. Fit a
plane to the patch the marker would cover and the largest deviation IS the gap under it:

        flat marker  --------------
                      \   gap    /
        curved skin    \________/

Gap grows with the SQUARE of marker size (a sphere of radius r sags a^2/2r over half-width a),
which is why the same spot is fine at 4cm and hopeless at 10cm. Always measure at the size you
will actually print.
"""

import numpy as np
import trimesh
from scipy.spatial import cKDTree

GLB = r"project/assets/avatar/mannequin.glb"
MARKER_SIZE = 0.10          # metres. MUST match aruco_patch_size in main_3d.gd.


# --------------------------------------------------------------------------------------
# 1. load + PCA
# --------------------------------------------------------------------------------------
scene = trimesh.load(GLB)
name = list(scene.geometry.keys())[0]
mesh = scene.geometry[name]
V = np.asarray(mesh.vertices)
VN = np.asarray(mesh.vertex_normals)

# The GLB node transform (mesh-local -> the frame Godot's `mannequin` node uses). trimesh's scene
# graph carries it; the .tscn instances the glb at ~identity, so this IS the Godot model frame.
T = next(scene.graph[n][0] for n in scene.graph.nodes_geometry if scene.graph[n][1] == name)

centroid = V.mean(0)
_, _, vt = np.linalg.svd(V - centroid, full_matrices=False)
SI, ML, AP = vt[0], vt[1], vt[2]   # 1st axis = longest = head<->chest, 2nd = across, 3rd = thin

print("=" * 78)
print("1. PCA  (the body's own axes, found from the vertices alone)")
for i, lbl in enumerate(["head<->chest", "shoulder<->shoulder", "front<->back"]):
    d = (V - centroid) @ vt[i]
    print("   axis %d  %-22s span %.3f m" % (i, lbl, d.max() - d.min()))

# Anatomical coords: x=ML (across), y=SI (up, +=head), z=AP (out of the chest).
#
# NOTE: stacking [ML, SI, AP] swaps two SVD rows, which FLIPS the determinant -> this frame is
# LEFT-handed. Directions still map correctly, but CROSS PRODUCTS come out mirrored. Build any
# marker axes in the model frame (below), never here. This bug cost me an hour: the marker "up"
# axis came out pointing at the feet.
A = np.stack([ML, SI, AP])
P = (V - centroid) @ A.T
N = VN @ A.T
print("   det(A) = %+.0f  (-1 = left-handed: do NOT take cross products in this frame)"
      % np.linalg.det(A))

# +SI must point at the head, not the chest. SVD gives an arbitrary sign, so pick it from the
# shape: the head end is NARROW, the chest end is WIDE. Compare only the extreme 20% at each end --
# comparing halves does not work, because the shoulders (the widest part of all) sit near the middle
# and land in whichever half, so the test just reads noise.
band = 0.2 * (P[:, 1].max() - P[:, 1].min())
hi = P[:, 1] > P[:, 1].max() - band
lo = P[:, 1] < P[:, 1].min() + band
w_hi = P[hi, 0].max() - P[hi, 0].min()
w_lo = P[lo, 0].max() - P[lo, 0].min()
print("   end widths: +y %.3f m   -y %.3f m   (head = the narrow end)" % (w_hi, w_lo))
if w_hi > w_lo:                      # +y end is the WIDE one -> that's the chest, so flip
    A = np.stack([ML, -SI, AP])
    P = (V - centroid) @ A.T
    N = VN @ A.T
    print("   (flipped SI so +y points at the head)")


# --------------------------------------------------------------------------------------
# 2. width profile -> label the body parts
# --------------------------------------------------------------------------------------
print("\n2. WIDTH PROFILE  (label parts from the shape: neck = narrowest, shoulders = widest)")
lo, hi = P[:, 1].min(), P[:, 1].max()
for a in np.arange(lo, hi, 0.06):
    sel = (P[:, 1] >= a) & (P[:, 1] < a + 0.06)
    if sel.sum() < 30:
        continue
    w = P[sel, 0].max() - P[sel, 0].min()
    bar = "#" * int(w * 60)
    print("   y %+.2f  width %.3f  %s" % (a, w, bar))


def region(y):
    """Height bands, read off the width profile above."""
    if y > 0.34: return "forehead"
    if y > 0.20: return "face (nose/eyes)"
    if y > 0.14: return "neck"
    if y > 0.04: return "clavicle"
    if y > -0.18: return "UPPER CHEST"
    return "LOWER CHEST"


# --------------------------------------------------------------------------------------
# 3. flatness = gap under a rigid marker of MARKER_SIZE
# --------------------------------------------------------------------------------------
tree = cKDTree(P)
# A square of side S has half-diagonal S*0.707 -- that is the disc the marker actually covers.
R = MARKER_SIZE * 0.707


def patch(c):
    """Fit a plane to the patch a marker at `c` would cover -> (gap_mm, tilt_deg, normal)."""
    nb = tree.query_ball_point(c, R)
    if len(nb) < 12:
        return None
    Q = P[nb]
    q = Q.mean(0)
    _, _, w = np.linalg.svd(Q - q, full_matrices=False)
    n = w[2] if w[2][2] > 0 else -w[2]              # point it out of the chest
    gap = np.abs((Q - q) @ w[2]).max() * 1000.0     # mm: furthest point from the plane
    tilt = np.degrees(np.arccos(np.clip(n[2], -1, 1)))
    return gap, tilt, n


print("\n3. BEST SPOT PER REGION  for a %.0f cm marker" % (MARKER_SIZE * 100))
print("   %-18s %8s %8s   %s" % ("region", "gap", "tilt", "anat x/y/z"))
best = {}
for i in np.where(N[:, 2] > 0.55)[0][::3]:          # only surfaces facing the camera
    r = patch(P[i])
    if r is None:
        continue
    k = region(P[i][1])
    if k not in best or r[0] < best[k][0]:
        best[k] = (r[0], r[1], P[i])
for k, (gap, tilt, p) in sorted(best.items(), key=lambda kv: kv[1][0]):
    flag = "  <-- good" if gap < 2.0 and tilt < 20 else ""
    print("   %-18s %5.1f mm %6.1f deg   (%+.3f, %+.3f, %+.3f)%s" % (k, gap, tilt, *p, flag))


# --------------------------------------------------------------------------------------
# 4. convert to the frame Godot's `mannequin` node uses
# --------------------------------------------------------------------------------------
def to_model(a):
    """anatomical point -> Godot model frame."""
    return (T @ np.append(A.T @ a + centroid, 1))[:3]


print("\n4. IN GODOT MODEL-FRAME COORDS  (what you'd type into the scene)")
picks = {k: v[2] for k, v in best.items() if v[0] < 2.0 and v[1] < 20}
for k, p in picks.items():
    print("   %-18s (%+.3f, %+.3f, %+.3f)" % (k, *to_model(p)))

if picks:
    c = np.mean([to_model(p) for p in picks.values()], axis=0)
    print("\n   centroid of those spots  = (%+.4f, %+.4f, %+.4f)" % tuple(c))
    print("   -> position_offset       = (%+.4f, %+.4f, %+.4f)" % tuple(-c))
    print("\n   (the rig anchors the avatar at the markers' centroid; the model's ORIGIN is not a")
    print("    body part -- it floats ~11cm behind the back -- so position_offset = -centroid")
    print("    slides the mesh onto the body.)")

print("\nSanity: the Godot `mannequin` node's AABB should read about")
print("   x -0.255..0.290   y 0..0.259   z -0.470..0.343")
print("If it doesn't, the importer moved something and every number above shifts with it.")
