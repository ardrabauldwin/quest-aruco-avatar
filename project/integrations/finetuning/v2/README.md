# Expanded speech examples

252 synthetic examples: 168 training, 84 validation, in English, German and Polish.
126 base sentences plus 126 neutral reporting-prefix variants. Examples were
authored and checked by the assistant; they are not real learner recordings or
clinician/native-speaker-reviewed labels.

Each translation family and its prefix variants stay entirely within one split.
The inspected old pilot test stays out of these files and is now development data.
There is a 24-case new synthetic challenge frozen before this training run.
It is not real-speaker validation. A later real-speaker test must be kept
out of training and hyperparameter selection.

Labels use the current app's action/kind/result/evidence schema. Normal breathing
and responsiveness are retained as opposite findings; the app must not progress
them as abnormal breathing/unresponsiveness. Ambiguous reports, plans, conflicting
findings and reports of multiple breaths do not confirm one completed action.

Regenerate and validate: `python integrations/finetuning/prepare_v2.py`.
Original pilot datasets and results are unchanged. A second local adapter has
been trained and evaluated; see RESULTS.md. It has not been deployed.
