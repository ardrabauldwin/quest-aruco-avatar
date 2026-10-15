"""Constraints for Marek kneeling down and taking over chest compressions (ERC
2025: a second rescuer compresses while the pads go on). One Kimodo take in two
text segments (sequencing, see prompts.tsv): kneeling down, then compressions.
During the compressions only the hands are pinned (end-effector constraints):
stacked on a lying adult's sternum 0.40 m in front of the hips, 0.23 m above the
floor at the top of each stroke and 5 cm lower at the bottom, 110/min; Kimodo
finds the body that does it. The pose that defines the hand targets has the
shoulders vertically above the hands and straight arms (grid-searched).
  ~/Projects/kimodo/.venv/bin/python data/motion/cpr_keyposes.py
Writes cpr_constraints.json. SOMA skeleton: Y up, Z forward, metres."""
import json
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation as Rot

from reach_keyposes import names, idx, fk, orient, standing, rx  # same skeleton helpers

HERE = Path(__file__).resolve().parent
FPS, RATE = 30, 110
KNEEL_S, CPR_S = 1.5, 6.0          # must match the durations in prompts.tsv
HANDS = np.array([0.0, 0.23, 0.40])  # top of the stroke, relative to the canonical origin
DEPTH = 0.05


def floor_height(L):
    _, J = fk(L, np.zeros(3))
    lowest = [J[idx[n], 1] for n in ("LeftShin", "RightShin", "LeftToeBase", "RightToeBase")]
    return 0.05 - min(lowest)


def compressing(push):
    L = standing()
    lean = 90
    L[idx["Hips"]] = rx(lean * .5)
    for bone in ("Spine1", "Spine2", "Chest"):
        L[idx[bone]] = rx(lean * .12)
    L[idx["Neck1"]] = rx(-12); L[idx["Head"]] = rx(-10)
    for side in ("Left", "Right"):
        L[idx[side + "Leg"]] = rx(-lean * .5 - 10)
        L[idx[side + "Shin"]] = rx(100)
        L[idx[side + "Foot"]] = rx(35)
    p = np.array([0, 0.0, 0.0])
    p[1] = floor_height(L) - DEPTH * push * 0.6   # the body drops into the stroke
    hands = HANDS - np.array([0, DEPTH * push, 0])
    for side, sign in (("Left", 1), ("Right", -1)):
        target = hands + np.array([sign * 0.015, 0.0, 0.0])
        _, J = fk(L, p)
        orient(L, p, side + "Arm", side + "ForeArm", target)
        orient(L, p, side + "ForeArm", side + "Hand", target + (target - J[idx[side + "Arm"]]) * 0.2)
    return L, p


if __name__ == "__main__":
    frames, poses = [], []
    half = FPS * 60 / RATE / 2
    t, push = (KNEEL_S + 0.4) * FPS, 0            # compressions start after kneeling down
    while t < (KNEEL_S + CPR_S) * FPS - 1:
        frames.append(int(round(t)))
        poses.append(compressing(push))
        t += half
        push = 1 - push
    rot = Rot.from_matrix(np.array([L for L, _ in poses]).reshape(-1, 3, 3)).as_rotvec().reshape(len(poses), len(names), 3)
    shared = {"frame_indices": frames, "root_positions": [p.tolist() for _, p in poses], "local_joints_rot": rot.tolist()}
    (HERE / "cpr_constraints.json").write_text(json.dumps([{"type": "left-hand", **shared}, {"type": "right-hand", **shared}]))
    print("cpr hand constraints", len(frames), "frames from", frames[0])
