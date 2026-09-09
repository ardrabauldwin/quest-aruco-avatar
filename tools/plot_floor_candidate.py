import json
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

root=Path(__file__).resolve().parents[1]
d=json.loads((root/'builds/floor_candidate_metrics.json').read_text())
phases=list(d['baseline'])
fig,axes=plt.subplots(1,2,figsize=(14,5),constrained_layout=True)
for ax,key,title in zip(axes,['shift_cm','spread_cm'],['Displacement from each method\'s front reference','Within-view spread (90% radius)']):
    x=np.arange(len(phases))
    for j,(mode,label,color) in enumerate([('baseline','Original reconstruction','#0072b2'),('candidate','Floor constraint before position','#d55e00')]):
        ax.bar(x+(j-.5)*.36,[d[mode][p]['filtered'][key] for p in phases],.36,label=label,color=color)
    ax.set_xticks(x,phases,rotation=35,ha='right');ax.set_ylabel('cm');ax.set_title(title);ax.legend();ax.grid(axis='y',alpha=.2)
fig.suptitle('Controlled offline replay: same temporal filter, different reconstruction\nNot measured headset output or absolute alignment accuracy')
fig.savefig(root/'builds/floor_candidate_comparison.png',dpi=160)
fig.savefig(root/'builds/floor_candidate_comparison.pdf')
