"""Report development measurements; no independent accuracy claim or deployment."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parent/'v5'
run=json.loads((ROOT/'pilot_run.json').read_text())
reg=json.loads((ROOT/'pilot_evaluation.json').read_text())
real=json.loads((ROOT/'real_development/pilot_evaluation.json').read_text())
lines=['# Version 5: recovered headset text','',
 'Trained Qwen/Qwen3-0.6B with rank-8 LoRA on 288 synthetic examples plus 6 genuine recognised headset outputs. Validation uses 117 synthetic examples. This tunes observation classification, not the live 4B conversation model or Whisper. No APK or production model was changed.','',
 'Two recovered outputs come from the same saved recording. Four come verbatim from earlier adb diagnostic outputs in this conversation. The historical recorder stopped during a USB interruption, so a full conversational archive does not exist. Source and uncertainty are preserved in recovered_real.jsonl. These labels describe ASR output, not verified original speech or physical actions. Human/native-speaker review is outstanding.','',
 '## Checkpoint selection','', '| Epoch | Synthetic validation loss |','|---|---:|']
for row in run['learning_curve']:
    if 'eval_loss' in row: lines.append(f"| {row['epoch']:.0f} | {row['eval_loss']:.6f} |")
lines += ['', f"Saved best validation checkpoint: `{run['best_checkpoint']}`. Training took {run['metrics']['train_runtime']:.1f} seconds. No test result was used for checkpoint selection.", '',
 '## Development checks','', '| Model | Previously inspected synthetic cases | False progression proposals | Real training outputs recalled |', '|---|---:|---:|---:|']
for key,title in [('adapter','Version 5'),('previous_adapter','Version 4')]:
    r=reg[key]; t=real[key]
    lines.append(f"| {title} | {r['correct']}/{r['total']} | {r['false_positives']} | {t['correct']}/{t['total']} |")
lines += ['',
 'The 36 synthetic cases were already inspected during version 4. The 6 real outputs were included in version 5 training. Neither result is an independent test, and recall of training sentences is not real-speaker generalisation. No percentage should be presented as validated headset accuracy. This does not show that adding the real outputs caused any improvement: random training trajectory and checkpoint selection also differ.', '',
 'A false progression proposal is a raw output on a non-action sentence, not an actual CCBM scenario transition. Deploying needs reviewed data and unseen sessions/speakers, with end-to-end ASR, interpretation and guard tests. The live qwen3:4b-instruct model remains unchanged.', '',
 '## Remaining regression errors','']
for case in reg['adapter']['cases']:
    if not case['correct']:
        lines += [f"### {case['id']}",'','Expected: `'+json.dumps(case['expected'],ensure_ascii=False)+'`','', 'Predicted: `'+json.dumps(case['prediction'],ensure_ascii=False)+'`','']
(ROOT/'RESULTS.md').write_text('\n'.join(lines),encoding='utf-8')
manifest=json.loads((ROOT/'manifest.json').read_text())
manifest['status']='trained_evaluated_development_only_not_deployed'
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2))
print(json.dumps({name:{key:dict(correct=r['correct'],total=r['total'],false_positives=r['false_positives']) for key,r in results.items()} for name,results in [('regression',reg),('training_recall',real)]}))
