"""Synthetic pilot labels, not clinician-reviewed learner data. Fixed split by wording."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SYSTEM = ('Classify a CPR trainee utterance. Return only JSON with action,kind,result,evidence. '
          'Evidence is an exact quote. Do not infer completion from questions, intentions, '
          'hypotheticals, contradictions or transcription errors. One observation maximum. '
          'Actions: begin_check,check_responsiveness,call_emergency,check_breathing,ventilation,compression_only,handover,none. '
          'Kinds: report,request,question,intention,uncertain,conversation. '
          'Results: safe,unresponsive,responsive,abnormal,normal,one_breath,none.')
# Each row has independently worded train/validation/test examples. No randomized
# near-duplicate splitting, stage hints, real recordings, or personal information.
GROUPS = [
 ('compression_only','request','none', ['Use compression only mode.','Switch to compression-only training.','Nur Herzdruckmassage, bitte.','Tylko uciski klatki piersiowej, proszę.'], ['Please use compressions without breaths.'], ['Can we continue in compression-only mode?']),
 ('handover','request','none', ['Hand over the patient.','Please end with a handover.','Patienten übergeben.','Przekaż pacjenta.'], ['Let us hand over to the arriving team.'], ['Please transfer care to the ambulance crew.']),
 ('begin_check','report','safe', ['The scene is safe.','I checked the area. It is safe.','It is safe to approach.','Die Umgebung ist sicher.','Miejsce jest bezpieczne.'], ['The surroundings are safe.'], ['I checked for hazards; it is safe here.']),
 ('check_responsiveness','report','unresponsive', ['He is not responding.','He does not respond to my voice.','He is unresponsive.','Er reagiert nicht.','Pacjent nie reaguje.'], ['There is no response when I speak to him.'], ['I spoke to him and tapped his shoulders. He did not respond.']),
 ('check_breathing','report','abnormal', ['He is not breathing normally.','He is not breathing.','He is only gasping.','Er atmet nicht normal.','Pacjent nie oddycha prawidłowo.'], ['His breathing is abnormal.'], ['I checked his breathing. There are only occasional gasps.']),
 ('ventilation','report','one_breath', ['I have given one rescue breath.','I gave the first breath.','I completed the second rescue breath.','Ich habe eine Beatmung gegeben.','Wykonałem jeden oddech ratowniczy.'], ['I have finished one rescue breath.'], ['The first rescue breath is completed.']),
 ('call_emergency','request','none', ['Anna, please call 112.','Please call emergency services.','Call 112 and put it on speaker.','Anna, ruf bitte 112 an.','Anno, zadzwoń pod 112.'], ['Could you call 112, Anna?'], ['Anna, contact the emergency services now, please.']),
 ('check_responsiveness','report','responsive', ['He is responding.','He answered me.','Er reagiert.','Pacjent reaguje.'], ['He responds to my voice.'], ['He opened his eyes and answered my question.']),
 ('check_breathing','report','normal', ['He is breathing normally.','His breathing is normal.','Er atmet normal.','Pacjent oddycha prawidłowo.'], ['I found normal breathing.'], ['I checked and he is taking regular normal breaths.']),
 ('none','intention','none', ['I will check breathing.','I am going to give a breath.','I will check if he responds.','Ich werde die Atmung prüfen.','Sprawdzę oddech.'], ['I plan to give the first rescue breath.'], ['Next I am going to assess responsiveness.']),
 ('none','question','none', ['Is he breathing?','What should I do?','How deep should I press?','Atmet er?','Czy on oddycha?'], ['Should I give a rescue breath?'], ['How can I tell if these gasps are normal?']),
 ('none','uncertain','none', ['He is responding and he is not responding.','I gave the first bread.','Maybe he is not breathing.','If he is unresponsive, I will call.','He is not responding and he is not breathing.'], ['We have given the first bread.'], ['I have given the first part of it.']),
 ('none','conversation','none', ['Hello Anna.','Thank you.','My name is Alex.','Hallo.','Dziękuję.'], ['Good afternoon.'], ['I am ready to listen.']),
]
TEST_LANGUAGES = [
 ['Bitte setzen wir die Übung ohne Beatmung fort.','Proszę kontynuować ćwiczenie bez oddechów ratowniczych.'],
 ['Übergeben Sie den Patienten bitte an das Rettungsteam.','Proszę przekazać pacjenta zespołowi ratowniczemu.'],
 ['Ich habe nach Gefahren geschaut. Hier ist es sicher.','Sprawdziłem otoczenie. Można bezpiecznie podejść.'],
 ['Ich habe ihn angesprochen und an den Schultern berührt. Keine Reaktion.','Zwróciłem się do niego i dotknąłem jego ramion. Nie reaguje.'],
 ['Bei der Atemkontrolle sehe ich nur vereinzeltes Schnappen nach Luft.','Sprawdziłem oddech. Widzę tylko pojedyncze westchnienia agonalne.'],
 ['Die erste Beatmung ist abgeschlossen.','Pierwszy oddech ratowniczy został wykonany.'],
 ['Anna, verständige jetzt bitte den Rettungsdienst.','Anno, proszę zadzwoń teraz po pogotowie.'],
 ['Er hat die Augen geöffnet und mir geantwortet.','Otworzył oczy i odpowiedział na moje pytanie.'],
 ['Ich habe geprüft: Er atmet regelmäßig und normal.','Sprawdziłem: oddycha regularnie i prawidłowo.'],
 ['Als Nächstes werde ich prüfen, ob er reagiert.','Następnie sprawdzę, czy reaguje.'],
 ['Wie erkenne ich, ob diese Atemzüge normal sind?','Jak rozpoznać, czy te oddechy są prawidłowe?'],
 ['Ich habe den ersten Teil davon gegeben.','Dałem pierwszą część tego.'],
 ['Ich bin bereit zuzuhören.','Jestem gotowy słuchać.'],
]

def main():
    seen = set()
    counts = {}
    for split, index in [('train',3),('validation',4),('test',5)]:
        rows = []
        for group_id, row in enumerate(GROUPS):
            action, kind, result = row[:3]
            utterances=row[index]+(TEST_LANGUAGES[group_id] if split=='test' else [])
            for utterance in utterances:
                assert utterance.casefold() not in seen, 'Split leakage'
                seen.add(utterance.casefold())
                label = dict(action=action, kind=kind, result=result, evidence=utterance)
                rows.append(dict(id=f'{split}-{group_id}-{len(rows)}', provenance='synthetic_draft_unreviewed',
                    utterance=utterance, label=label, messages=[dict(role='system',content=SYSTEM),
                    dict(role='user',content=utterance), dict(role='assistant',content=json.dumps(label,ensure_ascii=False))]))
        (ROOT / f'{split}.jsonl').write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in rows),encoding='utf-8')
        counts[split] = len(rows)
    print(counts)

if __name__ == '__main__': main()
