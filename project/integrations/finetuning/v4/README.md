# Version 4 experiment

This experiment targets indirect unresponsiveness reports, explanatory help requests and future breath reports. It preserves the original labeling convention and earlier versions. It does not change the Quest application.

Run from the parent finetuning directory in WSL with the installed training environment:

```sh
timeout 30 /opt/naret-training/bin/python prepare_v4.py
timeout 600 /opt/naret-training/bin/python train.py --data-dir v4 --output /opt/naret-training/v4-adapter --best-validation
timeout 600 /opt/naret-training/bin/python evaluate.py --data-dir v4 --adapter /opt/naret-training/v4-adapter --reference-adapter /opt/naret-training/v3-adapter
timeout 300 /opt/naret-training/bin/python check_app_schema.py --data-dir v4
timeout 30 /opt/naret-training/bin/python write_v4_report.py
```

The preparation command intentionally refuses to overwrite the frozen experiment. Results and learning curves are in `RESULTS.md`, `pilot_evaluation.json` and `pilot_run.json`. The saved adapter is the checkpoint selected by minimum validation loss, not test accuracy. Test labels and data must not be altered after inspecting predictions.

All sentences are synthetic and unreviewed. Family grouping and exact duplicate checks reduce leakage but cannot establish independence of semantic templates or eliminate overfitting. Real speakers, reviewed labels and end-to-end microphone tests remain necessary. This is an observation interpreter experiment, not general conversation fine-tuning.
