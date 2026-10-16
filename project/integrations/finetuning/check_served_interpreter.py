"""Replay v3 development cases through the actual serving endpoint before routing."""
import json
import urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parent
correct=0; false=0; cases=[]
def progresses(value):
    a=value.get('action'); k=value.get('kind'); r=value.get('result')
    return k=='request' and a in ['call_emergency','compression_only','handover'] or k=='report' and {'begin_check':'safe','check_responsiveness':'unresponsive','check_breathing':'abnormal','ventilation':'one_breath'}.get(a,'!')==r
for line in (ROOT/'v3/test.jsonl').read_text(encoding='utf-8').splitlines():
    row=json.loads(line)
    request=urllib.request.Request('http://127.0.0.1:8771/classify',data=json.dumps({'utterance':row['utterance']}).encode(),headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(request,timeout=25) as response: value=json.load(response)
    expected=row['label']
    passed=all(value.get(k)==expected[k] for k in ['action','kind','result'])
    bad=not progresses(expected) and progresses(value)
    correct+=passed; false+=bad
    cases.append(dict(id=row['id'],prediction=value,expected=expected,correct=passed,false_progression=bad))
result=dict(correct=correct,total=len(cases),false_progression=false,cases=cases,
    scope='known synthetic deployment regression; not new real-speaker validation')
(ROOT/'v3/serving_check.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(dict(correct=correct,total=len(cases),false_progression=false)))
raise SystemExit(0 if correct>=30 and false==0 else 1)
