"""Freeze v4 before training. Seen tests are excluded, translations stay together.

Help requests asking for an explanation use kind=question, including imperative
wording. Only explicit clinical/mode requests use kind=request. This preserves
the existing annotation convention; labels never change after model evaluation.
All examples are synthetic and require independent human review.
"""
import hashlib
import json
from prepare_v3 import ROOT, rows, Q, I, U, BREATH, MODE

UNRESP = ('check_responsiveness','report','unresponsive')
NORMAL = ('check_breathing','report','normal')
ABNORMAL = ('check_breathing','report','abnormal')
TRAIN = [
 (UNRESP, ['I called out and tapped his shoulders, but there was no response.', 'Ich habe ihn angesprochen und an den Schultern berührt, aber es kam keine Antwort.', 'Zawołałem i dotknąłem jego ramion, ale nie było odpowiedzi.']),
 (UNRESP, ['He gave me no reaction when I checked him.', 'Bei meiner Prüfung zeigte er keinerlei Reaktion.', 'Podczas sprawdzania nie wykazał żadnej reakcji.']),
 (UNRESP, ['I asked him to open his eyes. Nothing happened.', 'Ich bat ihn, die Augen zu öffnen. Es passierte nichts.', 'Poprosiłem go o otwarcie oczu. Nic się nie stało.']),
 (UNRESP, ['My responsiveness check is finished: no reaction at all.', 'Meine Prüfung der Reaktionsfähigkeit ist abgeschlossen: überhaupt keine Reaktion.', 'Zakończyłem sprawdzanie reakcji: zupełny brak reakcji.']),
 (Q, ['Explain how I should position my fingers, please.', 'Erkläre bitte, wie ich meine Finger halten soll.', 'Wyjaśnij proszę, jak mam ułożyć palce.']),
 (Q, ['Tell me what I should check next.', 'Sag mir, was ich als Nächstes prüfen soll.', 'Powiedz mi, co mam sprawdzić dalej.']),
 (Q, ['Help me understand how rescue breaths work.', 'Hilf mir zu verstehen, wie Beatmungen funktionieren.', 'Pomóż mi zrozumieć, jak wykonuje się oddechy ratownicze.']),
 (Q, ['Remind me where to press; do not switch modes.', 'Erinnere mich daran, wo ich drücken soll; ändere den Modus nicht.', 'Przypomnij mi, gdzie uciskać; nie zmieniaj trybu.']),
 (I, ['After I deliver a breath, I will let you know.', 'Nachdem ich eine Beatmung gegeben habe, werde ich Bescheid sagen.', 'Po wykonaniu oddechu dam znać.']),
 (I, ['The breath is not done. I will notify you later.', 'Die Beatmung ist nicht fertig. Ich sage später Bescheid.', 'Oddech nie jest zakończony. Powiadomię później.']),
 (I, ['I am going to check whether he reacts.', 'Ich werde prüfen, ob er reagiert.', 'Zamierzam sprawdzić, czy reaguje.']),
 (BREATH, ['That breath is finished; I delivered one.', 'Diese Beatmung ist beendet; ich habe eine gegeben.', 'Ten oddech jest zakończony; wykonałem jeden.']),
 (U, ['He did not react earlier, but now I am not sure.', 'Vorhin reagierte er nicht, aber jetzt bin ich unsicher.', 'Wcześniej nie reagował, ale teraz nie jestem pewien.']),
 (U, ['I heard the words one breath, but I did not say I gave it.', 'Ich hörte die Worte eine Beatmung, aber ich sagte nicht, dass ich sie gegeben habe.', 'Usłyszałem słowa jeden oddech, ale nie powiedziałem, że go wykonałem.']),
 (MODE, ['Activate the setting with chest compressions alone for me.', 'Aktiviere für mich die Einstellung mit ausschließlich Herzdruckmassage.', 'Włącz dla mnie ustawienie z samymi uciskami klatki piersiowej.']),
 (NORMAL, ['I checked him and his breaths look regular and normal.', 'Ich habe ihn geprüft und seine Atemzüge sind regelmäßig und normal.', 'Sprawdziłem go i oddycha regularnie i prawidłowo.']),
]
VALIDATION = [
 (UNRESP, ['I checked for a response and found absolutely nothing.', 'Ich prüfte seine Reaktion und stellte überhaupt nichts fest.', 'Sprawdziłem reakcję i nie stwierdziłem zupełnie nic.']),
 (Q, ['Describe the next action to me, please.', 'Beschreibe mir bitte die nächste Handlung.', 'Opisz mi proszę następną czynność.']),
 (I, ['You will hear from me after I finish giving the breath.', 'Ich melde mich, nachdem ich die Beatmung beendet habe.', 'Odezwę się po zakończeniu oddechu.']),
 (BREATH, ['I finished one breath a second ago.', 'Ich habe vor einer Sekunde eine Beatmung beendet.', 'Sekundę temu zakończyłem jeden oddech.']),
 (U, ['Maybe he responded; I cannot tell.', 'Vielleicht hat er reagiert; ich kann es nicht sagen.', 'Może zareagował; nie potrafię tego określić.']),
]
CHALLENGE = [
 (UNRESP, ['I shouted to him and touched his shoulder. He stayed completely unresponsive.', 'Ich rief ihn an und berührte seine Schulter. Er blieb völlig ohne Reaktion.', 'Zawołałem do niego i dotknąłem ramienia. Nadal zupełnie nie reagował.']),
 (UNRESP, ['There was zero reaction to my attempt to wake him.', 'Auf meinen Versuch, ihn zu wecken, gab es keinerlei Reaktion.', 'Na moją próbę obudzenia go nie było żadnej reakcji.']),
 (UNRESP, ['My check showed that he would neither answer nor move.', 'Meine Prüfung zeigte, dass er weder antwortete noch sich bewegte.', 'Sprawdzenie wykazało, że ani nie odpowiadał, ani się nie poruszał.']),
 (Q, ['Walk me through placing my hands before I start pressing.', 'Erkläre mir Schritt für Schritt die Handposition, bevor ich drücke.', 'Wyjaśnij krok po kroku ułożenie rąk, zanim zacznę uciskać.']),
 (Q, ['Tell me whether breaths are required in this mode.', 'Sag mir, ob in diesem Modus Beatmungen erforderlich sind.', 'Powiedz mi, czy w tym trybie oddechy są wymagane.']),
 (I, ['When the upcoming breath is over, I shall tell you the result.', 'Wenn die bevorstehende Beatmung vorbei ist, werde ich das Ergebnis melden.', 'Gdy nadchodzący oddech się skończy, zgłoszę wynik.']),
 (I, ['I still need to give that breath before reporting completion.', 'Ich muss diese Beatmung noch geben, bevor ich ihren Abschluss melde.', 'Muszę jeszcze wykonać ten oddech, zanim zgłoszę zakończenie.']),
 (BREATH, ['One rescue breath has now been delivered by me.', 'Eine Beatmung wurde jetzt von mir durchgeführt.', 'Jeden oddech ratowniczy został teraz przeze mnie wykonany.']),
 (U, ['I cannot verify that a breath actually happened.', 'Ich kann nicht bestätigen, dass tatsächlich eine Beatmung stattgefunden hat.', 'Nie mogę potwierdzić, że oddech rzeczywiście został wykonany.']),
 (NORMAL, ['After watching his chest, I found regular normal breathing.', 'Nach Beobachtung seines Brustkorbs stellte ich regelmäßige normale Atmung fest.', 'Po obserwacji klatki piersiowej stwierdziłem regularny prawidłowy oddech.']),
 (ABNORMAL, ['I assessed his breathing: there are gasps instead of normal breaths.', 'Ich beurteilte seine Atmung: Es gibt Schnappen nach Luft statt normaler Atemzüge.', 'Oceniłem oddech: łapie powietrze zamiast oddychać prawidłowo.']),
 (MODE, ['Choose the exercise option that consists solely of chest compressions.', 'Wähle die Übungsoption, die ausschließlich aus Herzdruckmassage besteht.', 'Wybierz opcję ćwiczenia obejmującą wyłącznie uciski klatki piersiowej.']),
]

def main():
    dest = ROOT/'v4'
    dest.mkdir(exist_ok=True)
    assert not (dest/'manifest.json').exists(), 'Do not overwrite a frozen experiment'
    sets = {s:[json.loads(l) for l in (ROOT/'v3'/f'{s}.jsonl').read_text(encoding='utf-8').splitlines()] for s in ['train','validation']}
    sets['train'] += rows(TRAIN,'v4-train')
    sets['validation'] += rows(VALIDATION,'v4-validation')
    sets['test'] = rows(CHALLENGE,'v4-challenge')
    old = {json.loads(l)['utterance'].casefold() for v in ['', 'v2/', 'v3/'] for l in (ROOT/f'{v}test.jsonl').read_text(encoding='utf-8').splitlines()}
    seen=set(); families=set()
    for split, items in sets.items():
        current={r['family'] for r in items}
        assert not families & current
        families |= current
        for r in items:
            key=r['utterance'].casefold()
            assert key not in seen and key not in old
            seen.add(key)
        (dest/f'{split}.jsonl').write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in items),encoding='utf-8')
    manifest=dict(counts={s:len(r) for s,r in sets.items()},test_sha256=hashlib.sha256((dest/'test.jsonl').read_bytes()).hexdigest(),status='frozen_before_training',human_reviewed=False,prior_tests='development_only',checkpoint_selection='minimum_validation_loss; test never selects checkpoint')
    (dest/'manifest.json').write_text(json.dumps(manifest,indent=2))
    print(json.dumps(manifest))

if __name__=='__main__': main()
