"""Summarise completed measurements; never alter labels or train on the challenge."""
import json
import statistics
from pathlib import Path
ROOT=Path(__file__).resolve().parent/'v3'
report=json.loads((ROOT/'pilot_evaluation.json').read_text(encoding='utf-8'))
lines=['# Version 3 results','',
 'Trained a new Qwen3-0.6B rank-8 LoRA adapter for three epochs on 240 synthetic training and 102 validation examples. Training took 107 seconds. Artifact: `/opt/naret-training/v3-adapter`. Previous experiments are preserved.','',
 'The 36 new synthetic cases (12 each English/German/Polish) were frozen before training. Models use identical test texts and system prompts, greedy generation, maximum 180 output tokens. These are text interpretation tests, not microphone, Whisper, full-app, learner or clinical validation.','',
 '| Model | Correct labels and quoted evidence | False progression proposals | Median inference seconds |',
 '|---|---:|---:|---:|']
for key,title in [('adapter','Version 3'),('previous_adapter','Version 2'),('app_model_schema','Current qwen3:4b-instruct, app observation schema'),('app_model','Current model, plain JSON comparison'),('base','Untuned Qwen3-0.6B')]:
    row=report[key]
    median=statistics.median(case['seconds'] for case in row['cases'])
    lines.append(f"| {title} | {row['correct']}/{row['total']} | {row['false_positives']} | {median:.3f} |")
lines+=['','The schema baseline uses the action/kind/result/evidence enums from the live local backend, with temperature 0 for a controlled comparison. The actual service uses temperature 0.35 and additional app routing/guards. BF16 Hugging Face generation and quantized Ollama/schema decoding remain different inference interfaces. Plain JSON underestimated the app model because it allowed invalid action names; preserve both measurements for transparency.','',
 'A false proposal means a raw model output suggests progression on a non-action sentence. It does not establish that CCBM or the live scenario advanced. Zero false proposals on this tiny synthetic set is not a reliability guarantee.','',
 'Version 3 made six strict-label errors, including missed unresponsiveness reports and question/intention category errors. It is a promising experimental interpreter, not a deployed or medically validated replacement. APK and live model unchanged.','',
 'These now-inspected test cases are development data. Do not use a future improved score on them as a fresh independent benchmark. Next validation needs independent speakers, real headset transcripts and broader held-out wording.','',
 '## Version 3 errors','']
for case in report['adapter']['cases']:
    if case['correct']: continue
    lines += [f"### {case['id']}",'','Expected: `'+json.dumps(case['expected'],ensure_ascii=False)+'`','',
              'Predicted: `'+json.dumps(case['prediction'],ensure_ascii=False)+'`','']
(ROOT/'RESULTS.md').write_text('\n'.join(lines),encoding='utf-8')
manifest=json.loads((ROOT/'manifest.json').read_text())
manifest.update(status='complete_not_deployed',challenge_status='now_inspected_development_data')
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('Saved v3 results and error review. No app deployment.')
