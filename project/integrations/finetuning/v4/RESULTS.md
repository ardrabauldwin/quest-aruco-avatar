# Version 4 results

Experimental Qwen3-0.6B rank-8 LoRA interpreter. 288 training, 117 validation and 36 new test examples across EN/DE/PL. Examples and labels are assistant-authored, synthetic and unreviewed. This trains observation classification, not Anna’s general conversation or speech recognition.

Related translations stay in one split. Previously inspected challenges are excluded. The new challenge was frozen before training and was not used to choose a checkpoint. Exact duplicate and translation-family overlap checks passed; semantic overlap and synthetic-author bias remain possible.

## Overfitting check

| Epoch | Validation loss |
|---|---:|
| 1 | 0.025011 |
| 2 | 0.031787 |
| 3 | 0.025529 |

Selected checkpoint: `/opt/naret-training/v4-adapter/checkpoint-72`. Training took 122.5 seconds. Validation loss worsened after epoch 1 despite falling training loss: a warning of overfitting. The saved adapter uses the best validation checkpoint, rather than the final epoch. This does not eliminate overfitting or establish real-speaker generalisation.

## Fresh text challenge

| Model | Exact labels and quoted evidence | False progression proposals |
|---|---:|---:|
| Version 4, best validation checkpoint | 30/36 | 2 |
| Version 3 | 29/36 | 1 |
| Current app model with observation schema | 24/36 | 2 |
| Untuned Qwen3-0.6B | 2/36 | 8 |

A false progression proposal is a raw model proposal on a non-action sentence, not a verified scenario transition. The current app baseline uses qwen3:4b-instruct with its native observation schema at temperature 0; actual runtime uses temperature 0.35 and additional routing/guards. The smaller BF16 adapters use greedy decoding. These are controlled text tests, not equivalent deployment interfaces or end-to-end headset tests.

APK, live model, tracking and calibration are unchanged. All test cases are now inspected development data. Next validation needs independently reviewed labels and real learner/headset transcripts before deployment.

## Version 4 errors

### v4-challenge-3-en

Expected: `{"action": "none", "kind": "question", "result": "none", "evidence": "Walk me through placing my hands before I start pressing."}`

Predicted: `{"action": "none", "kind": "conversation", "result": "none", "evidence": "Walk me through placing my hands before I start pressing."}`

### v4-challenge-5-pl

Expected: `{"action": "none", "kind": "intention", "result": "none", "evidence": "Gdy nadchodzący oddech się skończy, zgłoszę wynik."}`

Predicted: `{"action": "ventilation", "kind": "report", "result": "one_breath", "evidence": "Gdy nadchodzący oddech się skończy, zgłoszę wynik."}`

### v4-challenge-6-de

Expected: `{"action": "none", "kind": "intention", "result": "none", "evidence": "Ich muss diese Beatmung noch geben, bevor ich ihren Abschluss melde."}`

Predicted: `{"action": "compression_only", "kind": "request", "result": "none", "evidence": "Ich muss diese Beatmung noch geben, bevor ich meinen Abschluss melde."}`

### v4-challenge-6-pl

Expected: `{"action": "none", "kind": "intention", "result": "none", "evidence": "Muszę jeszcze wykonać ten oddech, zanim zgłoszę zakończenie."}`

Predicted: `{"action": "ventilation", "kind": "request", "result": "one_breath", "evidence": "Muszę jeszcze wykonać ten oddech, zanim zgłoszę zakończenie."}`

### v4-challenge-8-de

Expected: `{"action": "none", "kind": "uncertain", "result": "none", "evidence": "Ich kann nicht bestätigen, dass tatsächlich eine Beatmung stattgefunden hat."}`

Predicted: `{"action": "none", "kind": "question", "result": "none", "evidence": "Ich kann nicht bestätigen, dass tatsächlich eine Beatmung stattgefunden hat."}`

### v4-challenge-10-pl

Expected: `{"action": "check_breathing", "kind": "report", "result": "abnormal", "evidence": "Oceniłem oddech: łapie powietrze zamiast oddychać prawidłowo."}`

Predicted: `{"action": "ventilation", "kind": "report", "result": "abnormal", "evidence": "Oceniłem oddech: łapie powietrze zamiast oddychać prawidłowo."}`
