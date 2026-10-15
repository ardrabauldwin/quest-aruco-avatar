# Speech interpretation fine-tuning pilot

This trains observation extraction from TEXT, not Whisper, voices or CPR technique.
Qwen3-0.6B is a small feasibility pilot for the local 8 GB GPU, not a replacement
for the current app model or the requested 27B university-server experiment.

The dataset is synthetic and unreviewed: 61 training, 13 validation and 39 held-out
test examples. Training and testing include English, German and Polish. The tiny
test set cannot establish multilingual effectiveness. Wording is separate
between splits. Do not enlarge it by scattering nearly identical templates randomly
between train and test. Add independent learner utterances with speaker-grouped splits,
negations, questions, intentions, contradictions, ordinal breaths and noisy transcripts.
Human review and a substantially larger multilingual evaluation are required before use.

```bash
python prepare.py
python train.py --model Qwen/Qwen3-0.6B --output /opt/naret-training/pilot-adapter
python evaluate.py --adapter /opt/naret-training/pilot-adapter
```

Training uses assistant-only token loss and LoRA on q_proj/v_proj. All three epochs
use only train/validation. Evaluation runs the untouched base model and trained adapter
on the same held-out inputs. Check JSON validity, label correctness, evidence and false
positives; validation loss alone does not prove improved interpretation.

Dependencies installed in a separate WSL virtual environment `/opt/naret-training`:
torch, transformers==4.57.1, peft==0.17.1, accelerate==1.11.0.
Adapters and downloaded weights stay outside the app; no APK or live endpoint changes.
The existing CCBM and allowed-action guards remain mandatory after any future deployment.
