"""Fetch public pilot weights independently of GPU dependency installation."""
import os
import hashlib
import shutil
from pathlib import Path
os.environ['HF_HUB_DISABLE_XET']='1'
from huggingface_hub import snapshot_download

blob='f47f71177f32bcd101b7573ec9171e6a57f4f4d31148d38e382306f42996874b'
cache=Path.home()/'.cache/huggingface/hub/models--Qwen--Qwen3-0.6B/blobs'
partial=cache/(blob+'.incomplete')
candidates=list(cache.glob(blob+'.*.incomplete'))
if candidates and not partial.exists():
    shutil.copyfile(max(candidates,key=lambda p:p.stat().st_size),partial)
snapshot=Path(snapshot_download('Qwen/Qwen3-0.6B',allow_patterns=['*.json','*.safetensors','*.txt','*.jinja']))
digest=hashlib.file_digest((snapshot/'model.safetensors').open('rb'),'sha256').hexdigest()
assert digest==blob, 'Weight checksum failed; do not train or deploy'
print('Public model weight SHA256 verified:',digest)
