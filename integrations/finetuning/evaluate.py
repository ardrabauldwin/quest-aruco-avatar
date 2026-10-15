"""Compare untouched base and adapter on test data, never used for training."""
import argparse
import json
import time
import urllib.request
from pathlib import Path
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM
from peft import PeftModel

ROOT=Path(__file__).resolve().parent

def proposes_progression(label):
    if not isinstance(label,dict): return False
    if label.get('kind')=='request':
        return label.get('action') in ['call_emergency','compression_only','handover']
    return label.get('kind')=='report' and label.get('result')=={
        'begin_check':'safe','check_responsiveness':'unresponsive',
        'check_breathing':'abnormal','ventilation':'one_breath'}.get(label.get('action'),'INVALID')

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--adapter',default='/opt/naret-training/pilot-adapter')
    p.add_argument('--data-dir',type=Path,default=ROOT)
    p.add_argument('--app-model',default='')
    p.add_argument('--reference-adapter',default='')
    args=p.parse_args()
    model_id=json.loads(Path(args.adapter,'run.json').read_text())['model']
    tok=AutoTokenizer.from_pretrained(model_id)
    model=AutoModelForCausalLM.from_pretrained(model_id,torch_dtype=torch.bfloat16).to('cuda')
    model=PeftModel.from_pretrained(model,args.adapter).eval()
    if args.reference_adapter:
        model.load_adapter(args.reference_adapter,adapter_name='previous')
    cases=[json.loads(line) for line in (args.data_dir/'test.jsonl').read_text(encoding='utf-8').splitlines()]
    report={}
    for variant in ['base','adapter']+(['previous_adapter'] if args.reference_adapter else [])+(['app_model'] if args.app_model else []):
        model.set_adapter('previous' if variant=='previous_adapter' else 'default')
        results=[]
        for row in cases:
            prompt=tok.apply_chat_template(row['messages'][:2],tokenize=False,add_generation_prompt=True,enable_thinking=False)
            inputs=tok(prompt,return_tensors='pt').to('cuda')
            start=time.monotonic()
            if variant=='app_model':
                payload=dict(model=args.app_model,messages=row['messages'][:2],stream=False,think=False,format='json',options=dict(temperature=0,num_predict=180))
                request=urllib.request.Request('http://127.0.0.1:11434/api/chat',data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
                with urllib.request.urlopen(request,timeout=90) as response:
                    raw=json.load(response)['message']['content'].strip()
            else:
              with torch.inference_mode():
                if variant=='base':
                    with model.disable_adapter():
                        output=model.generate(**inputs,max_new_tokens=180,do_sample=False,pad_token_id=tok.eos_token_id)
                else: output=model.generate(**inputs,max_new_tokens=180,do_sample=False,pad_token_id=tok.eos_token_id)
              raw=tok.decode(output[0,inputs.input_ids.shape[1]:],skip_special_tokens=True).strip()
            try: predicted=json.loads(raw)
            except (ValueError,TypeError): predicted={}
            valid=isinstance(predicted,dict) and all(predicted.get(k)==row['label'][k] for k in ['action','kind','result'])
            evidence=isinstance(predicted,dict) and isinstance(predicted.get('evidence'),str) and bool(predicted['evidence']) and predicted['evidence'] in row['utterance']
            false_positive=not proposes_progression(row['label']) and proposes_progression(predicted)
            results.append(dict(id=row['id'],expected=row['label'],prediction=predicted,raw=raw,
                correct=valid and evidence,false_positive=false_positive,seconds=round(time.monotonic()-start,3)))
        report[variant]=dict(correct=sum(r['correct'] for r in results),total=len(results),
            false_positives=sum(r['false_positive'] for r in results),cases=results)
    output=Path(args.adapter,'heldout-evaluation.json')
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (args.data_dir/'pilot_evaluation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:{field:r[field] for field in ['correct','total','false_positives']} for k,r in report.items()}))

if __name__=='__main__': main()
