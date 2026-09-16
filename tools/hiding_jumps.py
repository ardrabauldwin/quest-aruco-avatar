"""For a hiding-recording replay: how far the avatar moved when the set of visible markers
changed. Compares the avatar position in the last second of each phase with the first
second of the next phase (phases: all_visible / common_hidden / chest_hidden / navel_hidden)."""
import csv, sys, numpy as np
def main(path):
    rows=[r for r in csv.DictReader(open(path,newline="")) if r["ready"]=="1"]
    if not rows: print(path,"no ready rows"); return
    t=np.array([float(r["time_s"]) for r in rows]); ph=[r["phase"] for r in rows]
    A=np.array([[float(r["avatar_x"]),float(r["avatar_y"]),float(r["avatar_z"])] for r in rows]); Y=np.array([float(r["avatar_yaw"]) for r in rows])
    segs=[]; start=0
    for i in range(1,len(ph)+1):
        if i==len(ph) or ph[i]!=ph[start]:
            segs.append((ph[start],start,i-1)); start=i
    print(path.split("/")[-1])
    tot=0.0; n=0
    for (p0,a0,b0),(p1,a1,b1) in zip(segs,segs[1:]):
        m0=(t>=t[b0]-1.0)&(np.arange(len(t))>=a0)&(np.arange(len(t))<=b0)
        m1=(t<=t[a1]+1.0)&(np.arange(len(t))>=a1)&(np.arange(len(t))<=b1)
        if m0.sum()<3 or m1.sum()<3: continue
        d=np.linalg.norm(np.median(A[m1],axis=0)-np.median(A[m0],axis=0))*100; dy=abs(((np.median(Y[m1])-np.median(Y[m0]))+180)%360-180)
        print(f"  {p0:14s} -> {p1:14s}  avatar moved {d:5.1f} cm, turned {dy:4.1f} deg"); tot+=d; n+=1
    print(f"  mean jump {tot/max(n,1):.1f} cm over {n} transitions")
if __name__=="__main__":
    for p in sys.argv[1:]: main(p)
