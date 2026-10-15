#!/bin/sh
# Real motion for the bystanders from NVIDIA Kimodo (SOMA-RP v1.1, mocap-trained).
# Writes <name>.bvh (standard T-pose rest) + <name>.npz next to this file.
cd "$(dirname "$0")"
while IFS="$(printf '\t')" read -r name seconds prompt; do
  [ -f "$name.bvh" ] && continue
  # Key poses authored in <name>_keyposes.py pin the motion; Kimodo interpolates.
  extra=""; [ -f "${name}_constraints.json" ] && extra="--constraints ${name}_constraints.json"
  "$HOME/Projects/kimodo/.venv/bin/kimodo_gen" "$prompt" --model Kimodo-SOMA-RP-v1.1 --duration "$seconds" \
    --diffusion_steps 80 --seed 7 $extra --output "$name" --bvh --bvh_standard_tpose && echo "NARET_MOTION $name"
done < prompts.tsv
