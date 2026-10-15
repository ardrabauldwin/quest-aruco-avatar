# Pilot error review

Assistant review of saved predictions, not clinician or native-speaker validation.
The inspected 39-case pilot test is now development data. Do not present a later score on it as a fresh independent benchmark.
Summary: {"Meaning or label error": 21}

Action: add independently worded examples for multi-sentence completed findings and polite requests. Preserve opposite findings; do not reinterpret intentions or noisy fragments as completed actions.

Do not fix an incorrect prediction by relabelling the gold sentence merely to agree with the model.


## test-0-0: Meaning or label error

Utterance: Can we continue in compression-only mode?

Expected: `{"action": "compression_only", "kind": "request", "result": "none", "evidence": "Can we continue in compression-only mode?"}`

Predicted: `{"action": "compression_only", "kind": "question", "result": "none", "evidence": "Can we continue in compression-only mode?"}`

False progression proposal: False

## test-0-2: Meaning or label error

Utterance: Proszę kontynuować ćwiczenie bez oddechów ratowniczych.

Expected: `{"action": "compression_only", "kind": "request", "result": "none", "evidence": "Proszę kontynuować ćwiczenie bez oddechów ratowniczych."}`

Predicted: `{"action": "none", "kind": "request", "result": "none", "evidence": "Proszę kontynuować ćwiczenie bez oddechów ratowniczych."}`

False progression proposal: False

## test-2-6: Meaning or label error

Utterance: I checked for hazards; it is safe here.

Expected: `{"action": "begin_check", "kind": "report", "result": "safe", "evidence": "I checked for hazards; it is safe here."}`

Predicted: `{"action": "none", "kind": "uncertain", "result": "none", "evidence": "I checked for hazards; it is safe here."}`

False progression proposal: False

## test-2-7: Meaning or label error

Utterance: Ich habe nach Gefahren geschaut. Hier ist es sicher.

Expected: `{"action": "begin_check", "kind": "report", "result": "safe", "evidence": "Ich habe nach Gefahren geschaut. Hier ist es sicher."}`

Predicted: `{"action": "check_breathing", "kind": "report", "result": "normal", "evidence": "Ich habe nach Gefahren geschaut. Hier ist es sicher."}`

False progression proposal: False

## test-2-8: Meaning or label error

Utterance: Sprawdziłem otoczenie. Można bezpiecznie podejść.

Expected: `{"action": "begin_check", "kind": "report", "result": "safe", "evidence": "Sprawdziłem otoczenie. Można bezpiecznie podejść."}`

Predicted: `{"action": "check_breathing", "kind": "report", "result": "normal", "evidence": "Sprawdziłem otoczenie. Można bezpiecznie podejść."}`

False progression proposal: False

## test-3-9: Meaning or label error

Utterance: I spoke to him and tapped his shoulders. He did not respond.

Expected: `{"action": "check_responsiveness", "kind": "report", "result": "unresponsive", "evidence": "I spoke to him and tapped his shoulders. He did not respond."}`

Predicted: `{"action": "none", "kind": "uncertain", "result": "none", "evidence": "I spoke to him and tapped his shoulders. He did not respond."}`

False progression proposal: False

## test-4-14: Meaning or label error

Utterance: Sprawdziłem oddech. Widzę tylko pojedyncze westchnienia agonalne.

Expected: `{"action": "check_breathing", "kind": "report", "result": "abnormal", "evidence": "Sprawdziłem oddech. Widzę tylko pojedyncze westchnienia agonalne."}`

Predicted: `{"action": "ventilation", "kind": "report", "result": "one_breath", "evidence": "Sprawdziłem oddech. Widzę tylko pojedyncze westchnienia agonalne."}`

False progression proposal: False

## test-5-15: Meaning or label error

Utterance: The first rescue breath is completed.

Expected: `{"action": "ventilation", "kind": "report", "result": "one_breath", "evidence": "The first rescue breath is completed."}`

Predicted: `{"action": "check_breathing", "kind": "report", "result": "normal", "evidence": "The first rescue breath is completed."}`

False progression proposal: False

## test-5-17: Meaning or label error

Utterance: Pierwszy oddech ratowniczy został wykonany.

Expected: `{"action": "ventilation", "kind": "report", "result": "one_breath", "evidence": "Pierwszy oddech ratowniczy został wykonany."}`

Predicted: `{"action": "check_breathing", "kind": "report", "result": "one_breath", "evidence": "Pierwszy oddech ratowniczy został wykonany."}`

False progression proposal: False

## test-6-19: Meaning or label error

Utterance: Anna, verständige jetzt bitte den Rettungsdienst.

Expected: `{"action": "call_emergency", "kind": "request", "result": "none", "evidence": "Anna, verständige jetzt bitte den Rettungsdienst."}`

Predicted: `{"action": "none", "kind": "request", "result": "none", "evidence": "Anna, verständige jetzt bitte den Rettungsdienst."}`

False progression proposal: False

## test-7-21: Meaning or label error

Utterance: He opened his eyes and answered my question.

Expected: `{"action": "check_responsiveness", "kind": "report", "result": "responsive", "evidence": "He opened his eyes and answered my question."}`

Predicted: `{"action": "check_breathing", "kind": "report", "result": "normal", "evidence": "He opened his eyes and answered my question."}`

False progression proposal: False

## test-7-22: Meaning or label error

Utterance: Er hat die Augen geöffnet und mir geantwortet.

Expected: `{"action": "check_responsiveness", "kind": "report", "result": "responsive", "evidence": "Er hat die Augen geöffnet und mir geantwortet."}`

Predicted: `{"action": "check_breathing", "kind": "report", "result": "abnormal", "evidence": "Er hat die Augen geöffnet und mir geantwortet."}`

False progression proposal: True

## test-7-23: Meaning or label error

Utterance: Otworzył oczy i odpowiedział na moje pytanie.

Expected: `{"action": "check_responsiveness", "kind": "report", "result": "responsive", "evidence": "Otworzył oczy i odpowiedział na moje pytanie."}`

Predicted: `{"action": "check_breathing", "kind": "report", "result": "one_breath", "evidence": "Otworzył oczy i odpowiedział na moje pytanie."}`

False progression proposal: False

## test-9-28: Meaning or label error

Utterance: Als Nächstes werde ich prüfen, ob er reagiert.

Expected: `{"action": "none", "kind": "intention", "result": "none", "evidence": "Als Nächstes werde ich prüfen, ob er reagiert."}`

Predicted: `{"action": "check_responsiveness", "kind": "request", "result": "none", "evidence": "Als Nächstes werde ich prüfen, ob er reagiert."}`

False progression proposal: False

## test-9-29: Meaning or label error

Utterance: Następnie sprawdzę, czy reaguje.

Expected: `{"action": "none", "kind": "intention", "result": "none", "evidence": "Następnie sprawdzę, czy reaguje."}`

Predicted: `{"action": "check_responsiveness", "kind": "report", "result": "responsive", "evidence": "Następnie sprawdzę, czy reaguje."}`

False progression proposal: False

## test-10-31: Meaning or label error

Utterance: Wie erkenne ich, ob diese Atemzüge normal sind?

Expected: `{"action": "none", "kind": "question", "result": "none", "evidence": "Wie erkenne ich, ob diese Atemzüge normal sind?"}`

Predicted: `{"action": "check_breathing", "kind": "question", "result": "none", "evidence": "Wie erkenne ich, ob diese Atemzüge normal sind?"}`

False progression proposal: False

## test-11-33: Meaning or label error

Utterance: I have given the first part of it.

Expected: `{"action": "none", "kind": "uncertain", "result": "none", "evidence": "I have given the first part of it."}`

Predicted: `{"action": "none", "kind": "intention", "result": "none", "evidence": "I have given the first part of it."}`

False progression proposal: False

## test-11-34: Meaning or label error

Utterance: Ich habe den ersten Teil davon gegeben.

Expected: `{"action": "none", "kind": "uncertain", "result": "none", "evidence": "Ich habe den ersten Teil davon gegeben."}`

Predicted: `{"action": "none", "kind": "intention", "result": "none", "evidence": "Ich habe den ersten Teil davon gegeben."}`

False progression proposal: False

## test-11-35: Meaning or label error

Utterance: Dałem pierwszą część tego.

Expected: `{"action": "none", "kind": "uncertain", "result": "none", "evidence": "Dałem pierwszą część tego."}`

Predicted: `{"action": "none", "kind": "intention", "result": "none", "evidence": "Dałem pierwszą część tego."}`

False progression proposal: False

## test-12-37: Meaning or label error

Utterance: Ich bin bereit zuzuhören.

Expected: `{"action": "none", "kind": "conversation", "result": "none", "evidence": "Ich bin bereit zuzuhören."}`

Predicted: `{"action": "none", "kind": "intention", "result": "none", "evidence": "Ich bin bereit zuzuhören."}`

False progression proposal: False

## test-12-38: Meaning or label error

Utterance: Jestem gotowy słuchać.

Expected: `{"action": "none", "kind": "conversation", "result": "none", "evidence": "Jestem gotowy słuchać."}`

Predicted: `{"action": "none", "kind": "intention", "result": "none", "evidence": "Jestem gotowy słuchać."}`

False progression proposal: False
