"""Key poses for Anna reaching for Jan (Drehbuch 1.13): upright, then bent from
the hips with straight legs and both hands toward the floor, held. Kimodo fills
in the motion between them. Runs in the Kimodo venv (numpy, scipy):
  ~/Projects/kimodo/.venv/bin/python data/motion/reach_keyposes.py
Writes reach_constraints.json. SOMA skeleton: Y up, Z forward, metres."""
import json
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation as Rot

HERE = Path(__file__).resolve().parent
sk = json.loads((HERE / "soma_skeleton.json").read_text())
names, par, N = sk["names"], sk["parents"], np.array(sk["neutral"])
idx = {n: i for i, n in enumerate(names)}
rx = lambda a: Rot.from_euler("x", a, degrees=True).as_matrix()
ry = lambda a: Rot.from_euler("y", a, degrees=True).as_matrix()
rz = lambda a: Rot.from_euler("z", a, degrees=True).as_matrix()


def fk(L, p):
    G = np.zeros_like(L); J = np.zeros((len(names), 3))
    for i in range(len(names)):
        if par[i] < 0: G[i] = L[i]; J[i] = p
        else: G[i] = G[par[i]] @ L[i]; J[i] = J[par[i]] + G[par[i]] @ (N[i] - N[par[i]])
    return G, J


def align(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b); c = np.dot(a, b); x = np.cross(a, b)
    if c > 1 - 1e-8: return np.eye(3)
    K = np.array([[0, -x[2], x[1]], [x[2], 0, -x[0]], [-x[1], x[0], 0]])
    return np.eye(3) + K + K @ K / (1 + c)


def orient(L, p, bone, child, target):
    G, J = fk(L, p); i, k = idx[bone], idx[child]
    L[i] = G[par[i]].T @ align(N[k] - N[i], np.array(target) - J[i])


def standing():
    L = np.repeat(np.eye(3)[None], len(names), axis=0)
    L[idx["LeftArm"]] = rz(-85); L[idx["RightArm"]] = rz(85)
    L[idx["LeftForeArm"]] = ry(-7); L[idx["RightForeArm"]] = ry(7)
    return L


def root_height(L):
    _, J = fk(L, np.zeros(3))
    return 0.015 - J[[idx[n] for n in ("LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot")], 1].min()


def reaching(lean):
    """Hip hinge: pelvis tips forward, spine follows, knees soft, arms hang toward the floor."""
    L = standing()
    L[idx["Hips"]] = rx(lean * .55)
    L[idx["Spine1"]] = rx(lean * .15); L[idx["Spine2"]] = rx(lean * .15); L[idx["Chest"]] = rx(lean * .15)
    L[idx["Neck1"]] = rx(-10); L[idx["Head"]] = rx(-8)
    for side in ("Left", "Right"):
        L[idx[side + "Leg"]] = rx(-lean * .55 - 4)   # legs stay near vertical under the tipped pelvis
        L[idx[side + "Shin"]] = rx(12)
        L[idx[side + "Foot"]] = rx(-8)
    p = np.array([0, 0.0, -0.06])
    p[1] = root_height(L)
    for side, sign in (("Left", 1), ("Right", -1)):
        _, J = fk(L, p)
        target = np.array([sign * 0.12, 0.30, 0.45])       # hands low and in front, toward Jan's hand
        orient(L, p, side + "Arm", side + "ForeArm", (J[idx[side + "Arm"]] + target) / 2)
        orient(L, p, side + "ForeArm", side + "Hand", target)
    return L, p


if __name__ == "__main__":
    up = standing(); up_p = np.array([0, root_height(up), 0])
    bent, bent_p = reaching(55)
    frames = [0, 36, 60, 89]
    poses = [(up, up_p), (bent, bent_p), (reaching(58)[0], bent_p), (bent, bent_p)]
    rot = Rot.from_matrix(np.array([L for L, _ in poses]).reshape(-1, 3, 3)).as_rotvec().reshape(len(poses), len(names), 3)
    (HERE / "reach_constraints.json").write_text(json.dumps([{"type": "fullbody", "frame_indices": frames,
        "root_positions": [p.tolist() for _, p in poses], "local_joints_rot": rot.tolist()}]))
    print("reach key poses at", frames)
