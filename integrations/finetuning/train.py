"""Small GPU LoRA pilot. Assistant-only loss; no automatic app deployment."""
import argparse
import json
import hashlib
from pathlib import Path
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM, Trainer, TrainingArguments, set_seed
from peft import LoraConfig, get_peft_model

ROOT = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', default='Qwen/Qwen3-0.6B')
    parser.add_argument('--output', default='/opt/naret-training/pilot-adapter')
    parser.add_argument('--data-dir',type=Path,default=ROOT)
    parser.add_argument('--best-validation',action='store_true',help='Save the epoch with lowest validation loss rather than always the last epoch')
    args = parser.parse_args()
    set_seed(42)
    assert torch.cuda.is_available(), 'GPU required; do not silently train on CPU'
    if args.model=='Qwen/Qwen3-0.6B':
        from huggingface_hub import hf_hub_download
        weight=Path(hf_hub_download(args.model,'model.safetensors'))
        with weight.open('rb') as file:
            assert hashlib.file_digest(file,'sha256').hexdigest()=='f47f71177f32bcd101b7573ec9171e6a57f4f4d31148d38e382306f42996874b', 'Model checksum failed'
    tokenizer = AutoTokenizer.from_pretrained(args.model)
    tokenizer.pad_token = tokenizer.eos_token
    model = AutoModelForCausalLM.from_pretrained(args.model, torch_dtype=torch.bfloat16)
    model.config.use_cache = False
    model = get_peft_model(model,LoraConfig(r=8,lora_alpha=16,lora_dropout=0.05,
        target_modules=['q_proj','v_proj'],task_type='CAUSAL_LM'))
    model.enable_input_require_grads()
    def load(split):
        samples=[]
        for line in (args.data_dir/f'{split}.jsonl').read_text(encoding='utf-8').splitlines():
            row=json.loads(line)
            prefix=tokenizer.apply_chat_template(row['messages'][:2],tokenize=False,add_generation_prompt=True,enable_thinking=False)
            # The target starts exactly after the generation prompt; only the answer trains.
            prompt=tokenizer.encode(prefix,add_special_tokens=False)
            answer=tokenizer.encode(row['messages'][2]['content']+tokenizer.eos_token,add_special_tokens=False)
            ids=prompt+answer
            assert len(ids)<=512
            samples.append(dict(input_ids=ids,attention_mask=[1]*len(ids),labels=[-100]*len(prompt)+answer))
        return samples
    def collate(samples):
        length=max(len(s['input_ids']) for s in samples)
        return {key:torch.tensor([s[key]+[pad]*(length-len(s[key])) for s in samples])
                for key,pad in [('input_ids',tokenizer.pad_token_id),('attention_mask',0),('labels',-100)]}
    training=TrainingArguments(output_dir=args.output,per_device_train_batch_size=1,
        per_device_eval_batch_size=1,gradient_accumulation_steps=4,num_train_epochs=3,
        learning_rate=2e-4,bf16=True,gradient_checkpointing=True,logging_steps=5,
        eval_strategy='epoch',save_strategy='epoch',save_total_limit=1,report_to='none',seed=42,
        load_best_model_at_end=args.best_validation,metric_for_best_model='eval_loss',greater_is_better=False)
    trainer=Trainer(model=model,args=training,train_dataset=load('train'),eval_dataset=load('validation'),data_collator=collate)
    result=trainer.train()
    trainer.save_model(args.output)
    tokenizer.save_pretrained(args.output)
    metadata=dict(model=args.model,metrics=result.metrics,
        gpu=torch.cuda.get_device_name(),torch_version=torch.__version__,seed=42,
        examples={'train':len(load('train')),'validation':len(load('validation'))},
        dataset_sha256={split:hashlib.sha256((args.data_dir/f'{split}.jsonl').read_bytes()).hexdigest()
                        for split in ['train','validation']},
        best_checkpoint=trainer.state.best_model_checkpoint,
        best_validation_loss=trainer.state.best_metric,
        learning_curve=trainer.state.log_history,
        status='experimental_unreviewed_not_deployed')
    Path(args.output,'run.json').write_text(json.dumps(metadata,indent=2))
    (args.data_dir/'pilot_run.json').write_text(json.dumps(metadata,indent=2))

if __name__ == '__main__': main()
