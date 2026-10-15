"""Add the production schema baseline without erasing plain-JSON measurements."""
import argparse
import json
import time
import urllib.request
from pathlib import Path
from evaluate import proposes_progression

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--data-dir',type=Path,required=True)
    args=parser.parse_args()
    properties={
      'action':{'type':'string','enum':['begin_check','check_responsiveness','call_emergency','check_breathing','ventilation','compression_only','handover','none']},
      'kind':{'type':'string','enum':['report','request','question','intention','uncertain','conversation']},
      'result':{'type':'string','enum':['safe','unresponsive','responsive','abnormal','normal','one_breath','none']},
      'evidence':{'type':'string','maxLength':1000}}
    schema=dict(type='object',properties=properties,required=list(properties),additionalProperties=False)
    results=[]
    for line in (args.data_dir/'test.jsonl').read_text(encoding='utf-8').splitlines():
        row=json.loads(line); start=time.monotonic()
        payload=dict(model='qwen3:4b-instruct',messages=row['messages'][:2],stream=False,think=False,format=schema,
            options=dict(temperature=0,num_predict=180,num_ctx=4096))
        request=urllib.request.Request('http://127.0.0.1:11434/api/chat',data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=90) as response: raw=json.load(response)['message']['content'].strip()
        try: prediction=json.loads(raw)
        except ValueError: prediction={}
        correct=isinstance(prediction,dict) and all(prediction.get(k)==row['label'][k] for k in ['action','kind','result'])
        evidence=isinstance(prediction,dict) and isinstance(prediction.get('evidence'),str) and bool(prediction['evidence']) and prediction['evidence'] in row['utterance']
        results.append(dict(id=row['id'],expected=row['label'],prediction=prediction,raw=raw,correct=correct and evidence,
            false_positive=not proposes_progression(row['label']) and proposes_progression(prediction),seconds=round(time.monotonic()-start,3)))
    path=args.data_dir/'pilot_evaluation.json'; report=json.loads(path.read_text(encoding='utf-8'))
    report['app_model_schema']=dict(correct=sum(r['correct'] for r in results),total=len(results),false_positives=sum(r['false_positive'] for r in results),cases=results)
    path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print({k:report['app_model_schema'][k] for k in ['correct','total','false_positives']})

if __name__=='__main__': main()
