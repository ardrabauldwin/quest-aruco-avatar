# Version 3 results

Trained a new Qwen3-0.6B rank-8 LoRA adapter for three epochs on 240 synthetic training and 102 validation examples. Training took 107 seconds. Artifact: `/opt/naret-training/v3-adapter`. Previous experiments are preserved.

The 36 new synthetic cases (12 each English/German/Polish) were frozen before training. Models use identical test texts and system prompts, greedy generation, maximum 180 output tokens. These are text interpretation tests, not microphone, Whisper, full-app, learner or clinical validation.

| Model | Correct labels and quoted evidence | False progression proposals | Median inference seconds |
|---|---:|---:|---:|
| Version 3 | 30/36 | 0 | 1.278 |
| Version 2 | 27/36 | 1 | 1.280 |
| Current qwen3:4b-instruct, app observation schema | 27/36 | 0 | 0.589 |
| Current model, plain JSON comparison | 19/36 | 0 | 0.592 |
| Untuned Qwen3-0.6B | 0/36 | 4 | 1.065 |

The schema baseline uses the action/kind/result/evidence enums from the live local backend, with temperature 0 for a controlled comparison. The actual service uses temperature 0.35 and additional app routing/guards. BF16 Hugging Face generation and quantized Ollama/schema decoding remain different inference interfaces. Plain JSON underestimated the app model because it allowed invalid action names; preserve both measurements for transparency.

A false proposal means a raw model output suggests progression on a non-action sentence. It does not establish that CCBM or the live scenario advanced. Zero false proposals on this tiny synthetic set is not a reliability guarantee.

Version 3 made six strict-label errors, including missed unresponsiveness reports and question/intention category errors. It is a promising experimental interpreter, not a deployed or medically validated replacement. APK and live model unchanged.

These now-inspected test cases are development data. Do not use a future improved score on them as a fresh independent benchmark. Next validation needs independent speakers, real headset transcripts and broader held-out wording.

## Version 3 errors

### challenge-v3-2-pl

Expected: `{"action": "none", "kind": "question", "result": "none", "evidence": "Proszę wyjaśnij ułożenie dłoni, zanim zacznę."}`

Predicted: `{"action": "none", "kind": "conversation", "result": "none", "evidence": "Proszę wyjaśnij ułożenie dłoni, zanim zacznę."}`

### challenge-v3-6-en

Expected: `{"action": "check_responsiveness", "kind": "report", "result": "unresponsive", "evidence": "I tried to get a reaction from him and got none."}`

Predicted: `{"action": "none", "kind": "uncertain", "result": "none", "evidence": "I tried to get a reaction from him and got none."}`

### challenge-v3-6-de

Expected: `{"action": "check_responsiveness", "kind": "report", "result": "unresponsive", "evidence": "Ich habe versucht, eine Reaktion von ihm zu bekommen, und bekam keine."}`

Predicted: `{"action": "none", "kind": "uncertain", "result": "none", "evidence": "Ich habe versucht, eine Reaktion von ihm zu bekommen, und bekam keine."}`

### challenge-v3-6-pl

Expected: `{"action": "check_responsiveness", "kind": "report", "result": "unresponsive", "evidence": "Próbowałem uzyskać od niego reakcję i nie uzyskałem żadnej."}`

Predicted: `{"action": "none", "kind": "uncertain", "result": "none", "evidence": "Próbowałem uzyskać od niego reakcję i nie uzyskałem żadnej."}`

### challenge-v3-10-de

Expected: `{"action": "none", "kind": "intention", "result": "none", "evidence": "Ich werde berichten, sobald ich die nächste Beatmung beendet habe."}`

Predicted: `{"action": "none", "kind": "uncertain", "result": "none", "evidence": "Ich werde berichten, sobald ich die nächste Beatmung beendet habe."}`

### challenge-v3-10-pl

Expected: `{"action": "none", "kind": "intention", "result": "none", "evidence": "Zgłoszę wynik, gdy zakończę następny oddech."}`

Predicted: `{"action": "none", "kind": "uncertain", "result": "none", "evidence": "Zgłoszę wynik, gdy zakończę następny oddech."}`
