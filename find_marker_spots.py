"""
Where on the mannequin can an ArUco marker actually sit flat?

    pip install trimesh numpy scipy
    python find_marker_spots.py

This answers ONE question: which areas of the body are flat enough for a marker of a given size.
It does NOT compute a Godot offset -- so there is no glTF node transform, no coordinate
conversion, and no scene-facing output. Everything stays in the body's own anatomical frame.
(For the offset, use analyze_mannequin.py, which adds that conversion.)

Three steps:
  1. PCA           -> the body's own axes (the mesh is authored tilted)
  2. Width profile -> label neck / clavicle / chest, purely from the shape
  3. Flatness      -> the GAP that opens under a rigid flat marker

The flatness number is the whole point. A marker is a rigid flat square; a chest is curved. Fit a
plane to the patch the marker would cover and the largest deviation IS the gap under it:

        flat marker  --------------
                      \   gap    /
        curved skin    \________/

Gap grows with the SQUARE of marker size, which is why a spot that is fine at 5 cm can be hopeless
at 10 cm. Always run this at the size you will actually print.
"""

import numpy as np
import trimesh
from scipy.spatial import cKDTree

GLB = r"project/assets/avatar/mannequin.glb"
MARKER_SIZE = 0.10          # metres -- the BLACK SQUARE, not the paper
GOOD_GAP_MM = 2.0           # a marker rocking on more than this will add pose error
GOOD_TILT_DEG = 20.0        # how far the surface may face away from the camera


# --------------------------------------------------------------------------------------
# 1. load + PCA  (find the body's own axes)
# --------------------------------------------------------------------------------------
scene = trimesh.load(GLB)
mesh = scene.geometry[list(scene.geometry.keys())[0]]
V = np.asarray(mesh.vertices)
VN = np.asarray(mesh.vertex_normals)

centroid = V.mean(0)
_, _, vt = np.linalg.svd(V - centroid, full_matrices=False)
SI, ML, AP = vt[0], vt[1], vt[2]   # longest = head<->chest, 2nd = across, 3rd = thin

print("=" * 70)
print("1. PCA  (body axes found from the vertices alone)")
for i, lbl in enumerate(["head<->chest", "shoulder<->shoulder", "front<->back"]):
    d = (V - centroid) @ vt[i]
    print("   axis %d  %-22s span %.3f m" % (i, lbl, d.max() - d.min()))

# Anatomical frame: x = across, y = up (+ = head), z = out of the chest.
A = np.stack([ML, SI, AP])
P = (V - centroid) @ A.T
N = VN @ A.T

# SVD gives an arbitrary sign, so pick it from the shape: the head end is NARROW, the chest end is
# WIDE. Compare only the extreme 20% -- comparing halves fails, because the shoulders (the widest
# part of all) sit near the middle and land in whichever half.
band = 0.2 * (P[:, 1].max() - P[:, 1].min())
hi = P[:, 1] > P[:, 1].max() - band
lo = P[:, 1] < P[:, 1].min() + band
if (P[hi, 0].max() - P[hi, 0].min()) > (P[lo, 0].max() - P[lo, 0].min()):
    A = np.stack([ML, -SI, AP])
    P = (V - centroid) @ A.T
    N = VN @ A.T
    print("   (flipped so +y points at the head)")


# --------------------------------------------------------------------------------------
# 2. width profile  ->  read the region boundaries off this by eye
# --------------------------------------------------------------------------------------
print("\n2. WIDTH PROFILE   dip = neck,  longest bar = shoulders")
for a in np.arange(P[:, 1].max(), P[:, 1].min(), -0.03):
    sel = (P[:, 1] >= a) & (P[:, 1] < a + 0.03)
    if sel.sum() < 20:
        continue
    w = P[sel, 0].max() - P[sel, 0].min()
    print("   y %+.2f  width %.3f  %s" % (a, w, "#" * int(w * 55)))


def region(y):
    """Height bands, READ OFF the width profile above by hand (specific to this mesh)."""
    if y > 0.34: return "forehead"
    if y > 0.20: return "face (nose/eyes)"
    if y > 0.14: return "neck"
    if y > 0.04: return "clavicle"
    if y > -0.18: return "UPPER CHEST"
    return "LOWER CHEST"


# --------------------------------------------------------------------------------------
# 3. flatness  =  the gap under a rigid marker
# --------------------------------------------------------------------------------------
tree = cKDTree(P)
R = MARKER_SIZE * 0.707      # a square of side S has half-diagonal S*0.707


def patch(c):
    """Fit a plane to the patch a marker at `c` covers -> (gap_mm, tilt_deg)."""
    nb = tree.query_ball_point(c, R)
    if len(nb) < 12:
        return None
    Q = P[nb]
    q = Q.mean(0)
    _, _, w = np.linalg.svd(Q - q, full_matrices=False)
    n = w[2] if w[2][2] > 0 else -w[2]              # point it out of the chest
    gap = np.abs((Q - q) @ w[2]).max() * 1000.0     # mm from the plane = the gap
    tilt = np.degrees(np.arccos(np.clip(n[2], -1, 1)))
    return gap, tilt


best = {}
for i in np.where(N[:, 2] > 0.55)[0][::3]:          # camera-facing surfaces only
    r = patch(P[i])
    if r is None:
        continue
    k = region(P[i][1])
    if k not in best or r[0] < best[k][0]:
        best[k] = (r[0], r[1], P[i])

print("\n3. BEST SPOT PER REGION  for a %.0f cm marker" % (MARKER_SIZE * 100))
print("   %-18s %8s %9s   %s" % ("region", "gap", "tilt", "anatomical x/y/z"))
for k, (gap, tilt, p) in sorted(best.items(), key=lambda kv: kv[1][0]):
    ok = gap < GOOD_GAP_MM and tilt < GOOD_TILT_DEG
    print("   %-18s %5.1f mm %6.1f deg   (%+.3f, %+.3f, %+.3f)%s"
          % (k, gap, tilt, *p, "   <-- usable" if ok else ""))

usable = [k for k, v in best.items() if v[0] < GOOD_GAP_MM and v[1] < GOOD_TILT_DEG]
print("\n   usable at %.0f cm: %s" % (MARKER_SIZE * 100, ", ".join(usable) if usable else "NONE"))
if not usable:
    print("   -> no area on this body is flat enough for a marker this big. Print smaller,")
    print("      or accept the gap (the marker will rock and add pose error).")
