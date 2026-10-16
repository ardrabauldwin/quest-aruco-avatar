"""Assistant-authored synthetic labels. Split entire translation/template families.

No learner recordings, human clinical review, or claimed independent benchmark.
The previously inspected pilot test is now development data, never a fresh test.
"""
import json
from pathlib import Path
from prepare import SYSTEM

ROOT = Path(__file__).resolve().parent
# Three independently worded families per label, each EN/DE/PL. The third
# family is validation. Prefix variants and translations always stay together.
GROUPS = [
('begin_check','report','safe',[
['I looked around and found no danger.','Ich habe mich umgesehen und keine Gefahr gefunden.','Rozejrzałem się i nie znalazłem zagrożenia.'],
['I checked the surroundings; we can approach safely.','Ich habe die Umgebung geprüft; wir können sicher näher kommen.','Sprawdziłem otoczenie; możemy bezpiecznie podejść.'],
['There are no hazards here, so it is safe to help.','Hier gibt es keine Gefahren, deshalb können wir sicher helfen.','Nie ma tu zagrożeń, więc możemy bezpiecznie pomóc.']]),
('check_responsiveness','report','unresponsive',[
['Sir, can you hear me? I tried speaking to him, but he did not answer.','Können Sie mich hören? Ich habe ihn angesprochen, aber er hat nicht geantwortet.','Czy mnie pan słyszy? Zwróciłem się do niego, ale nie odpowiedział.'],
['I tapped his shoulders and called to him. There was no reaction.','Ich habe seine Schultern berührt und ihn gerufen. Es gab keine Reaktion.','Dotknąłem jego ramion i zawołałem do niego. Nie było reakcji.'],
['He gives no response to my voice or my touch.','Er zeigt keine Reaktion auf meine Stimme oder Berührung.','Nie reaguje na mój głos ani dotyk.']]),
('check_breathing','report','abnormal',[
['I checked his breathing and he is not taking normal breaths.','Ich habe seine Atmung geprüft; er atmet nicht normal.','Sprawdziłem jego oddech; nie oddycha prawidłowo.'],
['He is gasping occasionally rather than breathing normally.','Er schnappt gelegentlich nach Luft, statt normal zu atmen.','Czasem łapie powietrze zamiast oddychać prawidłowo.'],
['I watched for breathing and could not detect any breaths.','Ich habe auf die Atmung geachtet und keine Atemzüge festgestellt.','Obserwowałem oddech i nie stwierdziłem żadnych oddechów.']]),
('ventilation','report','one_breath',[
['I have now delivered one rescue breath.','Ich habe jetzt eine Beatmung durchgeführt.','Wykonałem teraz jeden oddech ratowniczy.'],
['I finished giving the second breath just now.','Ich habe gerade die zweite Beatmung abgeschlossen.','Właśnie zakończyłem drugi oddech ratowniczy.'],
['One rescue breath has been given by me.','Eine Beatmung wurde von mir gegeben.','Podałem jeden oddech ratowniczy.']]),
('call_emergency','request','none',[
['Anna, would you phone an ambulance for us?','Anna, könntest du für uns den Rettungsdienst anrufen?','Anno, czy możesz wezwać dla nas pogotowie?'],
['Please dial 112 now and switch on the speaker.','Bitte wähle jetzt 112 und schalte den Lautsprecher ein.','Proszę wybierz teraz 112 i włącz głośnik.'],
['Could you contact emergency services immediately, Anna?','Könntest du sofort den Rettungsdienst verständigen, Anna?','Czy możesz natychmiast skontaktować się z pogotowiem, Anno?']]),
('compression_only','request','none',[
['Please select the option with chest compressions and no breaths.','Bitte wähle die Option mit Herzdruckmassage ohne Beatmung.','Proszę wybierz opcję ucisków klatki piersiowej bez oddechów.'],
['Could we switch this exercise to compressions only?','Könnten wir diese Übung auf reine Herzdruckmassage umstellen?','Czy możemy przełączyć to ćwiczenie na same uciski?'],
['I want to select compression-only mode for the exercise.','Ich möchte für die Übung den Modus ohne Beatmung auswählen.','Chcę wybrać dla ćwiczenia tryb samych ucisków.']]),
('handover','request','none',[
['Please let the arriving rescue team take over care.','Bitte lasse das eintreffende Rettungsteam die Versorgung übernehmen.','Proszę pozwól przybyłemu zespołowi ratowniczemu przejąć opiekę.'],
['I would like to hand this patient over to the emergency team.','Ich möchte diesen Patienten an das Rettungsteam übergeben.','Chciałbym przekazać tego pacjenta zespołowi ratowniczemu.'],
['Can we transfer the patient to the paramedics now?','Können wir den Patienten jetzt an die Rettungskräfte übergeben?','Czy możemy teraz przekazać pacjenta ratownikom?']]),
('check_responsiveness','report','responsive',[
['He answers when I call his name.','Er antwortet, wenn ich seinen Namen rufe.','Odpowiada, gdy wołam go po imieniu.'],
['After I spoke to him, he replied to me.','Nachdem ich ihn angesprochen habe, hat er mir geantwortet.','Gdy się do niego odezwałem, odpowiedział mi.'],
['He reacted to my shoulder tap and spoke.','Er hat auf die Berührung seiner Schulter reagiert und gesprochen.','Zareagował na dotknięcie ramienia i odezwał się.']]),
('check_breathing','report','normal',[
['His breaths are regular and normal; I checked them.','Seine Atemzüge sind regelmäßig und normal; ich habe sie geprüft.','Jego oddechy są regularne i prawidłowe; sprawdziłem je.'],
['I can see normal breathing after opening the airway.','Nach dem Öffnen der Atemwege sehe ich eine normale Atmung.','Po udrożnieniu dróg oddechowych widzę prawidłowy oddech.'],
['My breathing check found that he breathes normally.','Bei meiner Atemkontrolle habe ich festgestellt, dass er normal atmet.','Podczas kontroli oddechu stwierdziłem, że oddycha prawidłowo.']]),
('none','intention','none',[
['I will give the first rescue breath next.','Ich werde als Nächstes die erste Beatmung geben.','Następnie wykonam pierwszy oddech ratowniczy.'],
['I am about to ask Anna to phone for help.','Ich werde Anna gleich bitten, Hilfe anzurufen.','Zaraz poproszę Annę, żeby zadzwoniła po pomoc.'],
['I intend to check whether he answers me.','Ich beabsichtige zu prüfen, ob er mir antwortet.','Zamierzam sprawdzić, czy mi odpowiada.']]),
('none','question','none',[
['How should I check whether he responds?','Wie soll ich prüfen, ob er reagiert?','Jak mam sprawdzić, czy reaguje?'],
['Do I need to give another rescue breath?','Muss ich noch eine Beatmung geben?','Czy muszę wykonać jeszcze jeden oddech ratowniczy?'],
['Has someone already called an ambulance?','Hat schon jemand den Rettungsdienst angerufen?','Czy ktoś już wezwał pogotowie?']]),
('none','uncertain','none',[
['I think I gave a breath, but I am not sure.','Ich glaube, ich habe eine Beatmung gegeben, bin aber nicht sicher.','Chyba wykonałem oddech, ale nie jestem pewien.'],
['I gave one rescue bread.','Ich habe eine Beerdigung gegeben.','Podałem pierwszy chleb.'],
['If he stops responding, I will check his breathing.','Wenn er nicht mehr reagiert, werde ich seine Atmung prüfen.','Jeśli przestanie reagować, sprawdzę jego oddech.']]),
('none','uncertain','none',[
['He is breathing normally, but he is not breathing normally.','Er atmet normal, aber er atmet nicht normal.','Oddycha prawidłowo, ale nie oddycha prawidłowo.'],
['He is unresponsive and I have given one breath.','Er reagiert nicht und ich habe eine Beatmung gegeben.','Nie reaguje i wykonałem jeden oddech.'],
['I gave one breath and then completed a second breath.','Ich habe eine Beatmung gegeben und danach eine zweite abgeschlossen.','Wykonałem jeden oddech, a potem zakończyłem drugi.']]),
('none','conversation','none',[
['Anna, I know this is frightening for you.','Anna, ich weiß, dass das für dich beängstigend ist.','Anno, wiem, że to jest dla ciebie przerażające.'],
['Thank you for helping me, Anna.','Danke, dass du mir hilfst, Anna.','Dziękuję, że mi pomagasz, Anno.'],
['I am here with you, Anna.','Ich bin hier bei dir, Anna.','Jestem tutaj z tobą, Anno.']]),
]

def main():
    destination=ROOT/'v2'
    destination.mkdir(exist_ok=True)
    old_test={json.loads(line)['utterance'].casefold() for line in (ROOT/'test.jsonl').read_text(encoding='utf-8').splitlines()}
    splits={'train':[],'validation':[]}
    seen=set()
    for group,(action,kind,result,families) in enumerate(GROUPS):
        for family,translations in enumerate(families):
            split='validation' if family==2 else 'train'
            for language,base in zip(['en','de','pl'],translations):
                for variant,prefix in enumerate(['',{'en':'My report: ','de':'Meine Meldung: ','pl':'Moja informacja: '}[language]]):
                    text=prefix+base
                    assert text.casefold() not in seen and text.casefold() not in old_test
                    seen.add(text.casefold())
                    label=dict(action=action,kind=kind,result=result,evidence=text)
                    splits[split].append(dict(id=f'v2-{group}-{family}-{language}-{variant}',family=f'{group}-{family}',language=language,
                        provenance='assistant_authored_synthetic',human_reviewed=False,utterance=text,label=label,
                        messages=[dict(role='system',content=SYSTEM),dict(role='user',content=text),dict(role='assistant',content=json.dumps(label,ensure_ascii=False))]))
    for split,rows in splits.items():
        (destination/f'{split}.jsonl').write_text(''.join(json.dumps(row,ensure_ascii=False)+'\n' for row in rows),encoding='utf-8')
    train_families={r['family'] for r in splits['train']}
    assert not train_families & {r['family'] for r in splits['validation']}
    summary=dict(counts={k:len(v) for k,v in splits.items()},languages=['en','de','pl'],
        independent_base_sentences=sum(len(f)*3 for *_,f in GROUPS),
        human_reviewed=False,old_test_status='inspected_development_only',fresh_test_status='not_collected',
        note='Translations and prefix variants share a family and stay in the same split. No claimed real-user accuracy.')
    (destination/'manifest.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(json.dumps(summary))

if __name__=='__main__': main()
