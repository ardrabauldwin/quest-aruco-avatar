#!/usr/bin/env bash
set -euo pipefail
# Run as an unprivileged WSL user; stop with Ctrl+C. USB forwarding is separate.
cd /tmp
export LD_LIBRARY_PATH=/opt/naret-local-asr/whisper.cpp/build/src:/opt/naret-local-asr/whisper.cpp/build/ggml/src
exec /opt/naret-local-asr/whisper.cpp/build/bin/whisper-server \
  -m /opt/naret-local-asr/whisper.cpp/models/ggml-large-v3-turbo.bin \
  --host 127.0.0.1 --port 8767 --convert --no-context -t 8 -l auto
