"""Loopback-only serving of the selected v3 observation adapter, not dialogue."""
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM
from peft import PeftModel
from prepare import SYSTEM

MODEL='Qwen/Qwen3-0.6B'
ADAPTER='/opt/naret-training/v3-adapter'
tokenizer=AutoTokenizer.from_pretrained(MODEL,local_files_only=True)
model=AutoModelForCausalLM.from_pretrained(MODEL,torch_dtype=torch.bfloat16,local_files_only=True)
model=PeftModel.from_pretrained(model,ADAPTER).to('cuda').eval()
lock=threading.Lock()
ALLOWED={
    'action':{'begin_check','check_responsiveness','call_emergency','check_breathing','ventilation','compression_only','handover','none'},
    'kind':{'report','request','question','intention','uncertain','conversation'},
    'result':{'safe','unresponsive','responsive','abnormal','normal','one_breath','none'}}

def classify(payload):
    text=payload.get('utterance')
    if not isinstance(text,str) or not 1<=len(text)<=1000:
        raise ValueError('Invalid utterance')
    messages=[dict(role='system',content=SYSTEM),dict(role='user',content=text)]
    prompt=tokenizer.apply_chat_template(messages,tokenize=False,add_generation_prompt=True,enable_thinking=False)
    inputs=tokenizer(prompt,return_tensors='pt').to(model.device)
    if inputs.input_ids.shape[1]>512:
        raise ValueError('Utterance exceeds trained context; never silently truncate')
    with lock,torch.inference_mode():
        output=model.generate(**inputs,max_new_tokens=180,do_sample=False,pad_token_id=tokenizer.eos_token_id)
    raw=tokenizer.decode(output[0,inputs.input_ids.shape[1]:],skip_special_tokens=True).strip()
    result=json.loads(raw)
    if not isinstance(result,dict) or set(result)!={'action','kind','result','evidence'}:
        raise ValueError('Invalid output structure')
    if any(result.get(key) not in values for key,values in ALLOWED.items()):
        raise ValueError('Invalid output label')
    evidence=result.get('evidence')
    if not isinstance(evidence,str) or not evidence or evidence.casefold() not in text.casefold():
        raise ValueError('Evidence must quote the supplied utterance')
    return result

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def send(self,code,data):
        body=json.dumps(data,ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        self.send(200 if self.path=='/health' else 404,dict(model=MODEL,adapter=ADAPTER,scope='observation_interpretation'))
    def do_POST(self):
        if self.path!='/classify': self.send(404,{}); return
        try:
            length=int(self.headers.get('Content-Length','0'))
            if not 0<length<=8192: raise ValueError('Invalid size')
            self.send(200,classify(json.loads(self.rfile.read(length))))
        except (ValueError,TypeError):
            self.send(422,dict(error='invalid_interpretation'))
        except Exception:
            self.send(503,dict(error='interpreter_unavailable'))

if __name__=='__main__':
    ThreadingHTTPServer(('127.0.0.1',8771),Handler).serve_forever()
