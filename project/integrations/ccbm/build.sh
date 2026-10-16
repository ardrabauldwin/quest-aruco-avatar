#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out/build
# Install upstream CCBM and put its rc script on PATH first.
timeout 1200 rc -W -M FA -n 1000 -d d.pddl -p p.pddl -o d-observations \
  -w out/build -f out/p -C "-DUSE_ACTION_ESTIMATION"
timeout 120 out/p-analyzer -d 300 -o out/p.states
