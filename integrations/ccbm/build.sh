#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# Start from an empty build folder: CCBM does not recompile objects that depend on
# the generated model, so a changed model (e.g. a different number of actions)
# would otherwise be linked with stale objects.
rm -rf out/build
mkdir -p out/build
# Install upstream CCBM and put its rc script on PATH first.
timeout 1200 rc -W -M FA -n 1000 -d d.pddl -p p.pddl -o d-observations \
  -w out/build -f out/p -C "-DUSE_ACTION_ESTIMATION"
timeout 120 out/p-analyzer -d 300 -o out/p.states
