"""Plot labelled raw common-pose measurements and explicitly simulated filter outputs."""
import csv
import json
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'builds' / 'viewpoint_research'
OUT.mkdir(exist_ok=True)
PHASES = ['front','left','right','far_front','far_left','far_right','front_return']
MODES = ['current72','current90','no_prior72','fixed_rest72']
def read(mode):
    with (ROOT/'builds'/f'replay_{mode}.csv').open() as f:
        rows=list(csv.DictReader(f))
    return {k:np.array([r[k] for r in rows], dtype=str if k=='phase' else float) for k in rows[0]}
def xyz(d,p):return np.column_stack([d[p+'_'+a] for a in 'xyz'])
data={m:read(m) for m in MODES}
d=data['current72']; t=d['time_s']; raw=xyz(d,'raw')
base=np.median(raw[(d['phase']=='front')&(d['ready']==1)],axis=0)
base_yaw=np.median(d['raw_yaw'][(d['phase']=='front')&(d['ready']==1)])
def yaw(v):return np.rad2deg(np.angle(np.exp(1j*(v-base_yaw))))
plt.rcParams.update({'font.size':10,'axes.grid':True,'grid.alpha':.22})
summary=[]
fig,axes=plt.subplots(7,2,figsize=(15,22),constrained_layout=True)
for i,phase in enumerate(PHASES):
    mask=(d['phase']==phase); start=t[mask][0]
    eligible=mask&(t>=start+1)&(d['ready']==1)
    ax,ay=axes[i]
    for prefix,color,label in [('raw','#777777','Raw fused measurement'),('filtered','#0072b2','Current filter: offline replay')]:
        p=xyz(d,prefix)
        valid=mask&((d['ready']==1) if prefix=='filtered' else True)
        ax.plot(t[valid]-start,100*np.linalg.norm(p[valid]-base,axis=1),color=color,label=label,lw=1.3,alpha=.9)
        ay.plot(t[valid]-start,yaw(d[prefix+'_yaw'][valid]),color=color,lw=1.3,label=label)
        points=p[eligible]; median=np.median(points,axis=0)
        summary.append({'phase':phase,'series':prefix,'shift_from_front_reference_cm':float(100*np.linalg.norm(median-base)),
                        'scatter_p90_cm':float(100*np.percentile(np.linalg.norm(points-median,axis=1),90)), 'samples':len(points)})
    ax.set(title=phase.replace('_',' ').title(),ylabel='Displacement from front reference (cm)',xlabel='Time within label (s)')
    ay.set(title=phase.replace('_',' ').title()+' — heading',ylabel='Heading relative to front (degrees)',xlabel='Time within label (s)')
    ax.legend(fontsize=8);ay.legend(fontsize=8)
fig.suptitle('Each viewpoint: raw fused pose versus current-filter replay\nShared front reference; displacement is NOT absolute alignment error. Cold-start replay at 72 Hz.',fontsize=16)
fig.savefig(OUT/'each_view_before_after.png',dpi=150)
fig.savefig(OUT/'each_view_before_after.pdf')
plt.close(fig)

fig,axes=plt.subplots(3,1,figsize=(15,11),sharex=True,constrained_layout=True)
colors={'raw':'#999999','current72':'#0072b2','no_prior72':'#d55e00','fixed_rest72':'#009e73'}
names={'current72':'Current filter replay','no_prior72':'Rest pull disabled; automatic rest updates retained','fixed_rest72':'Rest frozen after initialization; pull retained'}
for j,a in enumerate('xyz'):
    axes[j].plot(t,(raw[:,j]-base[j])*100,color=colors['raw'],lw=.6,label='Raw fused measurement')
    for m in ['current72','no_prior72','fixed_rest72']:
        dd=data[m]; valid=dd['ready']==1
        axes[j].plot(dd['time_s'][valid],(dd['filtered_'+a][valid]-base[j])*100,color=colors[m],lw=1.3,label=names[m])
    axes[j].set_ylabel(f'World {a.upper()} displacement (cm)')
    for phase in PHASES:
        times=t[d['phase']==phase]
        axes[j].axvspan(times[0],times[-1],alpha=.05,color='blue')
    axes[j].legend(fontsize=8,loc='upper left')
axes[-1].set_xlabel('Recording time (s); shaded regions = standing labels, gaps = walking')
fig.suptitle('Whole experiment: filter comparisons — offline replay, not recorded avatar output',fontsize=15)
fig.savefig(OUT/'filter_comparison.png',dpi=150);fig.savefig(OUT/'filter_comparison.pdf');plt.close(fig)

fig,axes=plt.subplots(1,2,figsize=(14,5),constrained_layout=True)
for ax,key,title in zip(axes,['shift_from_front_reference_cm','scatter_p90_cm'],['Shift of median from shared front reference','Within-label spread: 90% radius around own median']):
    x=np.arange(7)
    for j,(prefix,color) in enumerate([('raw','#888888'),('filtered','#0072b2')]):
        vals=[next(s[key] for s in summary if s['phase']==p and s['series']==prefix) for p in PHASES]
        ax.bar(x+(j-.5)*.36,vals,.36,label='Raw fused' if j==0 else 'Current-filter replay',color=color)
    ax.set_xticks(x,PHASES,rotation=35,ha='right');ax.set_ylabel('cm');ax.set_title(title);ax.legend()
fig.suptitle('Stability and displacement are separate outcomes; neither establishes absolute accuracy')
fig.savefig(OUT/'summary.png',dpi=170);fig.savefig(OUT/'summary.pdf');plt.close(fig)

metrics={'reference_world_m':base.tolist(),'summary':summary,'comparisons':{}}
for m in MODES:
    dd=data[m]; metrics['comparisons'][m]={}
    for phase in PHASES:
        times=dd['time_s'][dd['phase']==phase];mask=(dd['phase']==phase)&(dd['time_s']>=times[0]+1)&(dd['ready']==1)
        p=xyz(dd,'filtered')[mask];mid=np.median(p,axis=0)
        metrics['comparisons'][m][phase]={'shift_cm':float(np.linalg.norm(mid-base)*100),'scatter_cm':float(np.percentile(np.linalg.norm(p-mid,axis=1),90)*100)}
(OUT/'metrics.json').write_text(json.dumps(metrics,indent=2))
print(json.dumps(metrics,indent=2))
