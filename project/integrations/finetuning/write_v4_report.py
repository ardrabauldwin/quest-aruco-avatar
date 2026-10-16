"""Report measured results and overfitting indicators without deploying anything."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parent/'v4'
run=json.loads((ROOT/'pilot_run.json').read_text())
report=json.loads((ROOT/'pilot_evaluation.json').read_text())
lines=['# Version 4 results','',
 'Experimental Qwen3-0.6B rank-8 LoRA interpreter. 288 training, 117 validation and 36 new test examples across EN/DE/PL. Examples and labels are assistant-authored, synthetic and unreviewed. This trains observation classification, not Anna’s general conversation or speech recognition.','',
 'Related translations stay in one split. Previously inspected challenges are excluded. The new challenge was frozen before training and was not used to choose a checkpoint. Exact duplicate and translation-family overlap checks passed; semantic overlap and synthetic-author bias remain possible.','',
 '## Overfitting check','', '| Epoch | Validation loss |','|---|---:|']
for row in run['learning_curve']:
    if 'eval_loss' in row:
        lines.append(f"| {row['epoch']:.0f} | {row['eval_loss']:.6f} |")
lines += ['',f"Selected checkpoint: `{run['best_checkpoint']}`. Training took {run['metrics']['train_runtime']:.1f} seconds. Validation loss worsened after epoch 1 despite falling training loss: a warning of overfitting. The saved adapter uses the best validation checkpoint, rather than the final epoch. This does not eliminate overfitting or establish real-speaker generalisation.",'',
 '## Fresh text challenge','', '| Model | Exact labels and quoted evidence | False progression proposals |','|---|---:|---:|']
for key,title in [('adapter','Version 4, best validation checkpoint'),('previous_adapter','Version 3'),('app_model_schema','Current app model with observation schema'),('base','Untuned Qwen3-0.6B')]:
    r=report[key]
    lines.append(f"| {title} | {r['correct']}/{r['total']} | {r['false_positives']} |")
lines += ['', 'A false progression proposal is a raw model proposal on a non-action sentence, not a verified scenario transition. The current app baseline uses qwen3:4b-instruct with its native observation schema at temperature 0; actual runtime uses temperature 0.35 and additional routing/guards. The smaller BF16 adapters use greedy decoding. These are controlled text tests, not equivalent deployment interfaces or end-to-end headset tests.', '',
 'APK, live model, tracking and calibration are unchanged. All test cases are now inspected development data. Next validation needs independently reviewed labels and real learner/headset transcripts before deployment.', '', '## Version 4 errors','']
for case in report['adapter']['cases']:
    if not case['correct']:
        lines += [f"### {case['id']}",'', 'Expected: `'+json.dumps(case['expected'],ensure_ascii=False)+'`','', 'Predicted: `'+json.dumps(case['prediction'],ensure_ascii=False)+'`','']
(ROOT/'RESULTS.md').write_text('\n'.join(lines),encoding='utf-8')
manifest=json.loads((ROOT/'manifest.json').read_text())
manifest.update(status='complete_not_deployed',challenge_status='now_inspected_development_data')
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2))
print(json.dumps({k:dict(correct=r['correct'],total=r['total'],false_positives=r['false_positives']) for k,r in report.items()}))
