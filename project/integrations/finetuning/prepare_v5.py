"""Mix recovered real ASR text with synthetic development examples.

This is not an independent real-speaker evaluation. The historical collector
stopped at a USB interruption. Four outputs are recovered verbatim from earlier
diagnostic tool results in this conversation, not invented learner dialogues.
Labels describe recognised text; audio truth and intended speech are unknown.
"""
import hashlib
import json
from prepare_v3 import ROOT, rows

def main():
    destination=ROOT/'v5'
    destination.mkdir(exist_ok=True)
    assert not (destination/'manifest.json').exists(), 'Do not overwrite an experiment'
    real=[]
    for line in (ROOT/'real_headset/candidates.jsonl').read_text(encoding='utf-8').splitlines():
        r=json.loads(line)
        real.append((r['utterance'],tuple(r['label_candidate'][key] for key in ['action','kind','result']),r['source'],r['family']))
    # Real model outputs previously inspected via adb logcat, recovered exactly.
    real += [
        ('See you next time.',('none','conversation','none'),'prior_adb_tool_output_in_chat','diagnostic-app-pid-20406'),
        ('Ich habe einen neuen Benefit.',('none','conversation','none'),'prior_adb_tool_output_in_chat','diagnostic-app-pid-20406'),
        ('I have given him one breath.',('ventilation','report','one_breath'),'prior_adb_tool_output_in_chat','diagnostic-app-pid-20406'),
        ('- Fine.',('none','conversation','none'),'prior_adb_tool_output_in_chat_20261013T002326','diagnostic-app-pid-23512'),
    ]
    recovered=[]
    for i,(text,label,source,family) in enumerate(real):
        r=rows([(label,[text])],f'real-v5-{i}')[0]
        r.update(provenance='real_headset_asr',source=source,family=family,
            language='de' if text.startswith('Ich ') else 'en',speaker_id='unknown',
            human_reviewed=False,audio_ground_truth_verified=False,
            label_basis='assistant-reviewed meaning of ASR output, not inferred learner intent',
            split='train_development_only')
        recovered.append(r)
    keys={r['utterance'].casefold() for r in recovered}
    sets={s:[json.loads(l) for l in (ROOT/'v4'/f'{s}.jsonl').read_text(encoding='utf-8').splitlines() if json.loads(l)['utterance'].casefold() not in keys] for s in ['train','validation']}
    sets['train']+=recovered
    # Already inspected v4 test is only a regression benchmark, never called new.
    sets['test']=[json.loads(l) for l in (ROOT/'v4/test.jsonl').read_text(encoding='utf-8').splitlines()]
    seen=set()
    for split,items in sets.items():
        for r in items:
            key=r['utterance'].casefold()
            assert key not in seen, 'Exact leakage or duplication'
            seen.add(key)
        (destination/f'{split}.jsonl').write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in items),encoding='utf-8')
    (destination/'recovered_real.jsonl').write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in recovered),encoding='utf-8')
    manifest=dict(counts={s:len(r) for s,r in sets.items()},real_asr_outputs=len(recovered),
        real_independent_recordings='unknown; two outputs are the same saved recording',
        actual_model='Qwen/Qwen3-0.6B',live_4b_model_unchanged=True,
        human_reviewed=False,real_data_split='all training/development; no independent real test',
        test_status='previously inspected synthetic regression set',
        test_sha256=hashlib.sha256((destination/'test.jsonl').read_bytes()).hexdigest(),
        status='prepared_not_trained',scope='observation classification, not general dialogue generation')
    (destination/'manifest.json').write_text(json.dumps(manifest,indent=2))
    print(json.dumps(manifest))

if __name__=='__main__': main()
