# Second fine-tuning experiment

Trained Qwen3-0.6B with rank-8 LoRA for three epochs using 168 synthetic training
and 84 validation examples. Training took 73 seconds on the local RTX 5060 Laptop
GPU. Artifact: `/opt/naret-training/v2-adapter`. Original pilot preserved.

The 24 new synthetic challenge cases were written and frozen before training.
Eight each are English, German and Polish. All models receive the same system
prompt and text; greedy decoding, maximum 180 generated tokens. Ollama's current
`qwen3:4b-instruct` receives a JSON-format request and thinking disabled. The
small Hugging Face models generate unconstrained text. This compares model
interpretation, not the complete app's phrase rules, speech capture, Whisper,
CCBM or state guards. Different models/quantizations/decoding interfaces remain
material limitations. No real learner or clinical validation is claimed.

| Model | Correct label and quoted evidence | False progression proposals | Median inference seconds |
|---|---:|---:|---:|
| Untuned Qwen3-0.6B | 0/24 | 1 | 1.026 |
| Second LoRA adapter | 16/24 | 2 | 1.308 |
| Current app model, qwen3:4b-instruct | 11/24 | 0 | 0.588 |

False proposals are raw model outputs that propose an action on a non-action
sentence; they do not establish that CCBM or the app actually advanced.
The adapter misclassified German and Polish hand-placement help questions as
compression-only mode requests. Higher overall accuracy does not justify
replacing the current app model when these false proposals increase.

Decision: do not deploy. APK and live services unchanged. These inspected challenge
cases are now development data; never report a future score on them as a fresh
unseen benchmark. Future training needs broader questions-versus-requests examples
and a separate real-speaker evaluation.

Raw results: `pilot_evaluation.json`. Training metadata: `pilot_run.json`.
