#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec /opt/naret-dialogue/bin/python "$SCRIPT_DIR/local_dialogue_server.py"
