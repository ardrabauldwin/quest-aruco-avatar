#!/usr/bin/env bash
set -euo pipefail
training_root=/opt/naret-training
source_root=/mnt/c/Users/bauld/Overlay/quest-aruco-avatar/builds/naret-migration/integrations/finetuning
echo installing > "$training_root/status.txt"
trap 'echo failed > "$training_root/status.txt"' ERR
timeout 7200 /opt/naret-dialogue/bin/uv pip install --python "$training_root/bin/python" torch transformers==4.57.1 peft==0.17.1 accelerate==1.11.0 >> "$training_root/install.log" 2>&1
echo training > "$training_root/status.txt"
timeout 1800 "$training_root/bin/python" "$source_root/train.py" > "$training_root/train.log" 2>&1
echo evaluating > "$training_root/status.txt"
timeout 900 "$training_root/bin/python" "$source_root/evaluate.py" > "$training_root/evaluate.log" 2>&1
echo complete > "$training_root/status.txt"
