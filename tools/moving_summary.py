"""Replay of a mannequin-moving recording: per phase, where the avatar stood and where the raw
fused markers said the mannequin was, both relative to the first stationary phase. The avatar
should stay put while only the viewer moves and follow when the markers move for good."""
import csv, sys, numpy as np
def main(path):
    rows=[r for r in csv.DictReader(open(path,newline="")) if r["ready"]=="1"]
    if not rows: print(path,"no ready rows"); return
    ph=[r["phase"] for r in rows]; order=list(dict.fromkeys(ph))
    A=np.array([[float(r["avatar_x"]),float(r["avatar_z"])] for r in rows]); R=np.array([[float(r["raw_x"]),float(r["raw_z"])] for r in rows])
    ref=[i for i,p in enumerate(ph) if p==order[0]]
    a0=np.median(A[ref],axis=0); r0=np.median(R[ref],axis=0)
    print(path.split("/")[-1], f"(reference: {order[0]})")
    for p in order:
        idx=[i for i,q in enumerate(ph) if q==p]
        if len(idx)<5: continue
        a=np.median(A[idx],axis=0)-a0; r=np.median(R[idx],axis=0)-r0
        gates=[rows[i].get("gate","") for i in idx]; g=max(set(gates),key=gates.count)
        print(f"  {p:22s} n={len(idx):4d}  avatar moved {np.linalg.norm(a)*100:5.1f} cm   raw markers moved {np.linalg.norm(r)*100:5.1f} cm   gate mostly: {g}")
if __name__=="__main__":
    for p in sys.argv[1:]: main(p)
