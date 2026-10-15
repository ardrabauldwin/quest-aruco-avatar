"""Produce a reproducible development error audit, without changing pilot results."""
import collections
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parent
report=json.loads((ROOT/'pilot_evaluation.json').read_text(encoding='utf-8'))
counts=collections.Counter()
lines=['# Pilot error review','',
 'Assistant review of saved predictions, not clinician or native-speaker validation.',
 'The inspected 39-case pilot test is now development data. Do not present a later score on it as a fresh independent benchmark.','']
for row in report['adapter']['cases']:
    if row['correct']: continue
    expected=row['expected']; predicted=row['prediction']
    if not isinstance(predicted,dict) or not all(k in predicted for k in ['action','kind','result','evidence']):
        category='Missing or invalid JSON schema'
    elif any(expected[k]!=predicted[k] for k in ['action','kind','result']):
        category='Meaning or label error'
    else:
        category='Evidence quote error'
    counts[category]+=1
    lines.extend([f"## {row['id']}: {category}",'',f"Utterance: {expected['evidence']}",'',
        'Expected: `'+json.dumps(expected,ensure_ascii=False)+'`','',
        'Predicted: `'+json.dumps(predicted,ensure_ascii=False)+'`','',
        'False progression proposal: '+str(row['false_positive']), ''])
lines[4:4]=['Summary: '+json.dumps(dict(counts)), '',
 'Action: add independently worded examples for multi-sentence completed findings and polite requests. Preserve opposite findings; do not reinterpret intentions or noisy fragments as completed actions.','',
 'Do not fix an incorrect prediction by relabelling the gold sentence merely to agree with the model.','']
(ROOT/'PILOT_ERROR_REVIEW.md').write_text('\n'.join(lines),encoding='utf-8')
print(dict(counts))
