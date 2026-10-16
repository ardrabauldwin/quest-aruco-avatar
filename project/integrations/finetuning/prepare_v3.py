"""Third synthetic experiment: contrast help questions and actual mode requests.

Preserves previous experiments. Old inspected challenges stay development data;
new challenge is frozen before training. No clinician/learner validation claimed.
"""
import json
import hashlib
from pathlib import Path
from prepare import SYSTEM

ROOT=Path(__file__).resolve().parent
Q=('none','question','none')
I=('none','intention','none')
U=('none','uncertain','none')
MODE=('compression_only','request','none')
BREATH=('ventilation','report','one_breath')
# Each triple is a translation family. Never scatter its languages across splits.
TRAIN=[
 (Q,['Where exactly do I put my palms on the chest?','Wo genau lege ich meine Handflächen auf den Brustkorb?','Gdzie dokładnie mam położyć dłonie na klatce piersiowej?']),
 (Q,['Can you explain the right hand position during compressions?','Kannst du die richtige Handposition während der Kompressionen erklären?','Czy możesz wyjaśnić prawidłowe ułożenie rąk podczas ucisków?']),
 (Q,['Should my hands be on top of each other?','Soll ich meine Hände übereinander legen?','Czy mam położyć jedną dłoń na drugiej?']),
 (Q,['How many compressions come before rescue breaths?','Wie viele Kompressionen kommen vor den Beatmungen?','Ile ucisków wykonuje się przed oddechami ratowniczymi?']),
 (Q,['Could you show me how to do chest compressions?','Könntest du mir zeigen, wie ich eine Herzdruckmassage durchführe?','Czy możesz mi pokazać, jak wykonywać uciski klatki piersiowej?']),
 (Q,['Do I need to keep my elbows straight?','Muss ich meine Ellenbogen gerade halten?','Czy muszę trzymać łokcie prosto?']),
 (Q,['How far should I push down on his chest?','Wie weit soll ich seinen Brustkorb nach unten drücken?','Jak głęboko mam uciskać jego klatkę piersiową?']),
 (Q,['Can you explain when I should give the next breath?','Kannst du erklären, wann ich die nächste Beatmung geben soll?','Czy możesz wyjaśnić, kiedy mam wykonać następny oddech?']),
 (Q,['What does compression-only mode mean?','Was bedeutet der Modus nur mit Herzdruckmassage?','Co oznacza tryb samych ucisków?']),
 (Q,['Is compression-only mode an option?','Ist der Modus ohne Beatmung eine Option?','Czy tryb bez oddechów jest dostępny?']),
 (Q,['Should I switch to compression-only mode?','Soll ich auf den Modus ohne Beatmung umstellen?','Czy powinienem przełączyć się na tryb bez oddechów?']),
 (Q,['Can you teach me compressions without changing the exercise mode?','Kannst du mir Kompressionen erklären, ohne den Übungsmodus zu ändern?','Czy możesz wyjaśnić uciski bez zmiany trybu ćwiczenia?']),
 (MODE,['Please activate the compression-only exercise setting.','Bitte aktiviere die Übungseinstellung nur mit Herzdruckmassage.','Proszę włącz ustawienie ćwiczenia z samymi uciskami.']),
 (MODE,['Change my selected training mode to compression-only.','Ändere meinen gewählten Trainingsmodus auf nur Herzdruckmassage.','Zmień wybrany tryb treningu na same uciski.']),
 (MODE,['I choose the mode that omits rescue breaths; please enable it.','Ich wähle den Modus ohne Beatmung; bitte schalte ihn ein.','Wybieram tryb bez oddechów ratowniczych; proszę go włączyć.']),
 (MODE,['Would you select compression-only mode for this session?','Würdest du für diese Sitzung den Modus ohne Beatmung auswählen?','Czy możesz wybrać dla tej sesji tryb bez oddechów?']),
 (I,['I will complete the second breath in a moment.','Ich werde die zweite Beatmung gleich abschließen.','Za chwilę zakończę drugi oddech.']),
 (I,['I have not performed a breath yet; I am about to start.','Ich habe noch keine Beatmung durchgeführt; ich fange gleich an.','Jeszcze nie wykonałem oddechu; zaraz zacznę.']),
 (U,['I might have completed a rescue breath, but I cannot confirm it.','Vielleicht habe ich eine Beatmung abgeschlossen, aber ich kann es nicht bestätigen.','Może zakończyłem oddech ratowniczy, ale nie mogę tego potwierdzić.']),
 (U,['Please change the mode, or perhaps leave it; I am undecided.','Bitte ändere den Modus oder lass ihn vielleicht so; ich bin unentschlossen.','Proszę zmienić tryb albo może go zostawić; nie jestem zdecydowany.']),
 (BREATH,['I have completed exactly one rescue breath now.','Ich habe jetzt genau eine Beatmung abgeschlossen.','Zakończyłem teraz dokładnie jeden oddech ratowniczy.']),
 (('check_breathing','report','normal'),['I observed his breathing and it is normal.','Ich habe seine Atmung beobachtet und sie ist normal.','Obserwowałem jego oddech i jest prawidłowy.']),
 (('check_breathing','report','abnormal'),['I checked: he only gasps and has no normal breathing.','Ich habe geprüft: Er schnappt nur nach Luft und atmet nicht normal.','Sprawdziłem: tylko łapie powietrze i nie oddycha prawidłowo.']),
 (('check_responsiveness','report','unresponsive'),['Can you hear me, sir? I checked and he does not react.','Können Sie mich hören? Ich habe geprüft und er reagiert nicht.','Czy mnie pan słyszy? Sprawdziłem i nie reaguje.']),
]
VALIDATION=[
 (Q,['Which part of my hand belongs on the sternum?','Welcher Teil meiner Hand gehört auf das Brustbein?','Którą część dłoni mam położyć na mostku?']),
 (Q,['Can you remind me how to press correctly?','Kannst du mich daran erinnern, wie ich richtig drücke?','Czy możesz przypomnieć mi, jak prawidłowo uciskać?']),
 (MODE,['Set this training session to the no-breaths mode, please.','Stelle diese Trainingssitzung bitte auf den Modus ohne Beatmung.','Ustaw tę sesję treningową na tryb bez oddechów, proszę.']),
 (I,['The first breath is still to be done; I will give it now.','Die erste Beatmung steht noch aus; ich werde sie jetzt geben.','Pierwszy oddech jest jeszcze do wykonania; wykonam go teraz.']),
 (U,['I am not certain that I delivered a breath successfully.','Ich bin nicht sicher, dass ich eine Beatmung erfolgreich gegeben habe.','Nie jestem pewien, czy skutecznie wykonałem oddech.']),
 (BREATH,['I just finished delivering a single rescue breath.','Ich habe gerade eine einzelne Beatmung fertig durchgeführt.','Właśnie zakończyłem wykonywanie jednego oddechu ratowniczego.']),
]
CHALLENGE=[
 (Q,['What position should my wrists be in when pressing?','In welcher Position sollen meine Handgelenke beim Drücken sein?','W jakiej pozycji powinny być nadgarstki podczas uciskania?']),
 (Q,['Why do we alternate compressions and breaths?','Warum wechseln wir zwischen Kompressionen und Beatmungen?','Dlaczego przeplatamy uciski i oddechy?']),
 (Q,['Please explain the hand placement before I begin.','Bitte erkläre die Handposition, bevor ich anfange.','Proszę wyjaśnij ułożenie dłoni, zanim zacznę.']),
 (Q,['Is there a setting without ventilation, and how does it work?','Gibt es eine Einstellung ohne Beatmung und wie funktioniert sie?','Czy jest ustawienie bez oddechów i jak ono działa?']),
 (MODE,['For this exercise, enable the option for compressions without ventilation.','Aktiviere für diese Übung die Option für Kompressionen ohne Beatmung.','Włącz dla tego ćwiczenia opcję ucisków bez oddechów.']),
 (('call_emergency','request','none'),['Anna, arrange an emergency ambulance by calling 112, please.','Anna, organisiere bitte einen Rettungswagen, indem du 112 anrufst.','Anno, wezwij proszę karetkę, dzwoniąc pod 112.']),
 (('check_responsiveness','report','unresponsive'),['I tried to get a reaction from him and got none.','Ich habe versucht, eine Reaktion von ihm zu bekommen, und bekam keine.','Próbowałem uzyskać od niego reakcję i nie uzyskałem żadnej.']),
 (('check_breathing','report','normal'),['My assessment is that his breathing is normal and regular.','Meine Beurteilung ist, dass seine Atmung normal und regelmäßig ist.','Moja ocena jest taka, że oddycha prawidłowo i regularnie.']),
 (('check_breathing','report','abnormal'),['His only breathing movements are gasps; I found no normal breaths.','Seine einzigen Atembewegungen sind Schnappen nach Luft; ich fand keine normalen Atemzüge.','Jego jedyne ruchy oddechowe to łapanie powietrza; nie stwierdziłem prawidłowych oddechów.']),
 (BREATH,['I gave the patient a single rescue breath just a moment ago.','Ich habe dem Patienten gerade einen einzelnen Atemstoß zur Beatmung gegeben.','Przed chwilą wykonałem u pacjenta jeden oddech ratowniczy.']),
 (I,['I will report back once I have finished the next breath.','Ich werde berichten, sobald ich die nächste Beatmung beendet habe.','Zgłoszę wynik, gdy zakończę następny oddech.']),
 (U,['I cannot remember whether I actually completed the first breath.','Ich kann mich nicht erinnern, ob ich die erste Beatmung tatsächlich abgeschlossen habe.','Nie pamiętam, czy naprawdę zakończyłem pierwszy oddech.']),
]

def rows(groups,prefix):
    output=[]
    for family,(label,texts) in enumerate(groups):
        for lang,text in zip(['en','de','pl'],texts):
            target=dict(zip(['action','kind','result'],label)); target['evidence']=text
            output.append(dict(id=f'{prefix}-{family}-{lang}',family=f'{prefix}-{family}',language=lang,provenance='assistant_synthetic_unreviewed',human_reviewed=False,utterance=text,label=target,messages=[dict(role='system',content=SYSTEM),dict(role='user',content=text),dict(role='assistant',content=json.dumps(target,ensure_ascii=False))]))
    return output

def main():
    destination=ROOT/'v3'; destination.mkdir(exist_ok=True)
    assert not (destination/'manifest.json').exists(), 'Keep frozen experiments immutable'
    sets={split:[json.loads(l) for l in (ROOT/f'v2/{split}.jsonl').read_text(encoding='utf-8').splitlines()] for split in ['train','validation']}
    sets['train']+=rows(TRAIN,'focus-train'); sets['validation']+=rows(VALIDATION,'focus-validation')
    sets['test']=rows(CHALLENGE,'challenge-v3')
    old_tests={json.loads(l)['utterance'].casefold() for version in ['', 'v2/'] for l in (ROOT/f'{version}test.jsonl').read_text(encoding='utf-8').splitlines()}
    seen=set(); families=set()
    for split,items in sets.items():
        current_families={r['family'] for r in items}; assert not families & current_families; families|=current_families
        for row in items:
            key=row['utterance'].casefold(); assert key not in seen and key not in old_tests; seen.add(key)
        (destination/f'{split}.jsonl').write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in items),encoding='utf-8')
    manifest=dict(counts={k:len(v) for k,v in sets.items()},test_sha256=hashlib.sha256((destination/'test.jsonl').read_bytes()).hexdigest(),status='frozen_before_training',human_reviewed=False,prior_tests='development_only',purpose='help_questions_vs_mode_requests')
    (destination/'manifest.json').write_text(json.dumps(manifest,indent=2))
    print(json.dumps(manifest))

if __name__=='__main__': main()
