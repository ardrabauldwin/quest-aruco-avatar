# Third observation-interpreter experiment

This trains language interpretation, not hand tracking, Whisper or Anna's voice.
The base is the same small Qwen3-0.6B pilot model, not a 27B university model.
Adapter: `/opt/naret-training/v3-adapter`. Previous adapters are preserved.

240 synthetic training examples and 102 validation examples, in English, German
and Polish. Includes the v2 split plus independently worded contrast families:
hand-position/depth/breath help questions, questions about modes, explicit mode
selection requests, future actions, uncertainty and completed reports.
Translations remain together in one split. No clinician, native-speaker or
real-learner validation is claimed.

A 36-case synthetic challenge was frozen before this training run. No inspected
pilot/v2 challenge text was copied into train, validation or this challenge.
Training is three epochs, rank-8 LoRA, seed 42, assistant-only token loss. Evaluation
compares untuned base, v3 adapter, v2 adapter and the current app's
`qwen3:4b-instruct` on identical prompts and texts. Local inference differences
(BF16 Hugging Face versus quantized Ollama with JSON formatting) remain limitations.
The benchmark does not include the app's phrase grammar, help routing, Whisper,
CCBM or allowed-action guards. False proposals do not prove an actual app transition.

Reproduce using `/opt/naret-training/bin/python`:

```bash
python train.py --data-dir v3 --output /opt/naret-training/v3-adapter
python evaluate.py --data-dir v3 --adapter /opt/naret-training/v3-adapter --reference-adapter /opt/naret-training/v2-adapter --app-model qwen3:4b-instruct
```

See `pilot_run.json`, `pilot_evaluation.json`, and `RESULTS.md` for recorded results.
The APK and live model are not automatically changed by this experiment.
