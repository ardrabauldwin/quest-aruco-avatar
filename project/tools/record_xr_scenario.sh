#!/bin/sh
# Records build/xr_scenario.mp4: Drehbuch scenario 1 with the Meta XR Simulator's hands.
set -e
cd "$(dirname "$0")/.."
PY=${XRSIM_PY:-python3}   # needs grpcio + protobuf
rm -rf build/xr_scenario
# Silent: the dummy driver still mixes (clip timing works), nothing reaches the speakers.
godot --path . --xr-mode on --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy \
	--script tools/record_xr_scenario.gd > build/xr_scenario.log 2>&1 &
GODOT=$!
PORT=""
for _ in $(seq 60); do
	[ -n "$PORT" ] && break
	sleep 1
	PORT=$(lsof -nP -a -p $GODOT -iTCP -sTCP:LISTEN 2>/dev/null | grep -oE '\]:[0-9]+' | cut -c3- | head -1)
done
[ -n "$PORT" ] || { echo "simulator did not start"; kill $GODOT; exit 1; }
"$PY" tools/xr_hand_driver.py "$PORT"
wait $GODOT
"$PY" tools/mux_xr_video.py xr_scenario
