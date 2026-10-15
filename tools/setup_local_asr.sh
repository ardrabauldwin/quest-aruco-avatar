#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/naret-local-asr"
cd "$HOME/naret-local-asr"
if [ ! -d whisper.cpp ]; then
  timeout 120 git clone --depth 1 --branch v1.8.2 https://github.com/ggml-org/whisper.cpp.git
fi
cd whisper.cpp
timeout 120 cmake -B build -DWHISPER_BUILD_SERVER=ON -DGGML_NATIVE=OFF -DGGML_CUDA=OFF
timeout 300 cmake --build build --config Release -j 4
timeout 900 bash models/download-ggml-model.sh large-v3
