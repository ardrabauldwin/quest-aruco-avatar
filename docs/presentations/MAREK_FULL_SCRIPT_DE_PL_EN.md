# Marek: complete original fixed dialogue

Source: Denis baseline commit 9d880a1, data/bystander_lines.json. German and Polish are verbatim; English is a translation prepared for this review. Event-triggered script, not a single linear conversation. Marek is inactive in the current one-witness app.

## 1. marek_offer
- German: Ich bin hier. Was soll ich tun?
- Polish: Jestem tutaj. Co mam robić?
- English translation: I’m here. What should I do?
- Trigger: After accepted responsiveness assessment, with a 2.5-second delay.
- Original voice style: [calm, determined]

## 2. marek_call
- German: Ich rufe die 112 an und stelle auf Lautsprecher.
- Polish: Dzwonię pod 112 i włączam głośnik.
- English translation: I’m calling 112 and putting it on speakerphone.
- Trigger: Accepted emergency-call action.
- Original voice style: [calm]

## 3. marek_dispatch
- German: Die Leitstelle ist dran. Sie fragen, ob er normal atmet.
- Polish: Dyspozytor jest na linii. Pyta, czy on normalnie oddycha.
- English translation: The dispatcher is on the line. They’re asking whether he is breathing normally.
- Trigger: Five seconds after the emergency-call action.
- Original voice style: [calm, focused]

## 4. marek_prompt_call
- German: Soll ich den Notruf wählen?
- Polish: Mam zadzwonić na numer alarmowy?
- English translation: Should I call the emergency number?
- Trigger: CALL_HELP: no call after 15 seconds.
- Original voice style: [helpful]

## 5. marek_go_aed
- German: Ich hole den Defibrillator!
- Polish: Idę po defibrylator!
- English translation: I’ll get the defibrillator!
- Trigger: Accepted AED request.
- Original voice style: [urgent]

## 6. marek_prompt_aed
- German: Soll ich einen Defibrillator suchen?
- Polish: Mam poszukać defibrylatora?
- English translation: Should I look for a defibrillator?
- Trigger: During CPR, call made but no AED requested: more than 20 seconds since the call.
- Original voice style: [helpful]

## 7. marek_back_aed
- German: Hier ist der AED! Machen Sie ihn an.
- Polish: Tu jest AED! Proszę go włączyć.
- English translation: Here is the AED! Turn it on.
- Trigger: Return with AED after the fetch sequence; travel affects timing.
- Original voice style: [out of breath]

## 8. marek_faster
- German: Die Leitstelle sagt: schneller drücken!
- Polish: Dyspozytor mówi: szybciej uciskać!
- English translation: The dispatcher says: press faster!
- Trigger: Four consecutive rate samples below 98 BPM after warm-up; call/phone available; cooldown.
- Original voice style: [urgent]

## 9. marek_slower
- German: Etwas langsamer, sagt die Leitstelle.
- Polish: Trochę wolniej, mówi dyspozytor.
- English translation: A little slower, says the dispatcher.
- Trigger: Four consecutive rate samples above 124 BPM after warm-up; call/phone available; cooldown.
- Original voice style: [calm]

## 10. marek_position
- German: Die Hände in die Mitte der Brust, sagt die Leitstelle.
- Polish: Ręce na środek klatki piersiowej, mówi dyspozytor.
- English translation: Hands in the centre of the chest, says the dispatcher.
- Trigger: Three consecutive off-target strokes; call/phone available; cooldown.
- Original voice style: [calm, clear]

## 11. marek_resume
- German: Das Gerät sagt: sofort weiterdrücken!
- Polish: Urządzenie mówi: natychmiast uciskać dalej!
- English translation: The device says: resume compressions immediately!
- Trigger: Post-shock inactivity longer than five seconds.
- Original voice style: [urgent, firm]

## 12. marek_swap
- German: Ich kann beim Drücken übernehmen, wenn Sie nicht mehr können.
- Polish: Mogę zmienić przy uciskaniu, jeśli trzeba.
- English translation: I can take over compressions if you can’t continue.
- Trigger: Analysis-due event during CPR; this line offers help rather than accepting a swap.
- Original voice style: [calm, supportive]

## 13. marek_ems
- German: Der Rettungsdienst ist da.
- Polish: Karetka już jest.
- English translation: The ambulance crew is here.
- Trigger: Handover, or eight seconds after simulated recovery/ROSC.
- Original voice style: [relieved]

## 14. marek_take_over
- German: Ich drücke weiter – kleben Sie die Elektroden!
- Polish: Ja uciskam dalej – proszę naklejać elektrody!
- English translation: I’ll keep doing compressions—attach the pads!
- Trigger: AED handoff/helper-compression sequence.
- Original voice style: [urgent, determined]
