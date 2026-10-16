"""Freeze a small new synthetic challenge before the v2 training run."""
import json
from pathlib import Path
from prepare import SYSTEM
ROOT=Path(__file__).resolve().parent
groups=[
('check_responsiveness','report','unresponsive',['I asked him to open his eyes and he gave no response.','Ich bat ihn, die Augen zu öffnen; er zeigte keine Reaktion.','Poprosiłem go, żeby otworzył oczy; nie zareagował.']),
('check_breathing','report','abnormal',['After checking, I found no normal breaths at all.','Nach der Kontrolle habe ich keine normale Atmung festgestellt.','Po sprawdzeniu nie stwierdziłem prawidłowego oddechu.']),
('ventilation','report','one_breath',['The rescue breath I just performed is finished.','Die von mir gerade durchgeführte Beatmung ist beendet.','Oddech ratowniczy, który właśnie wykonałem, jest zakończony.']),
('call_emergency','request','none',['Anna, could you get emergency help on the phone?','Anna, könntest du telefonisch den Rettungsdienst verständigen?','Anno, czy możesz telefonicznie wezwać pogotowie?']),
('none','intention','none',['I have not given the breath yet; I will do it next.','Ich habe die Beatmung noch nicht gegeben; ich werde sie als Nächstes durchführen.','Jeszcze nie wykonałem oddechu; zrobię to za chwilę.']),
('none','uncertain','none',['I cannot tell whether his breathing is normal.','Ich kann nicht sagen, ob seine Atmung normal ist.','Nie potrafię stwierdzić, czy oddycha prawidłowo.']),
('check_breathing','report','normal',['He takes normal breaths; that is what I found during the check.','Er atmet normal; das habe ich bei der Kontrolle festgestellt.','Oddycha prawidłowo; to stwierdziłem podczas kontroli.']),
('none','question','none',['How can I position my hands for the next compressions?','Wie soll ich meine Hände für die nächsten Kompressionen positionieren?','Jak mam ułożyć ręce do następnych ucisków?']),
]
destination=ROOT/'v2/test.jsonl'
assert not destination.exists(), 'Do not overwrite a frozen challenge'
seen={json.loads(line)['utterance'].casefold() for split in ['train','validation'] for line in (ROOT/f'v2/{split}.jsonl').read_text(encoding='utf-8').splitlines()}
rows=[]
for group,(action,kind,result,texts) in enumerate(groups):
 for language,text in zip(['en','de','pl'],texts):
    assert text.casefold() not in seen
    label=dict(action=action,kind=kind,result=result,evidence=text)
    rows.append(dict(id=f'challenge-{group}-{language}',language=language,provenance='new_synthetic_challenge_unreviewed',utterance=text,label=label,messages=[dict(role='system',content=SYSTEM),dict(role='user',content=text),dict(role='assistant',content=json.dumps(label,ensure_ascii=False))]))
destination.write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in rows),encoding='utf-8')
print('Frozen',len(rows),'new challenge cases; not real-speaker validation.')
