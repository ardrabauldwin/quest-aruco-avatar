GODOT ?= godot

.PHONY: setup import test smoke run offline apk benchmark
setup:
	python3 tools/setup_dependencies.py --download-vendors
import:
	$(GODOT) --headless --xr-mode off --path . --editor --import --quit
test: import
	$(GODOT) --headless --xr-mode off --path . --script tests/run_tests.gd
smoke: import
	NARET_OFFLINE=1 $(GODOT) --headless --xr-mode off --path . -- --smoke-test
run:
	python3 tools/run_local.py --xr-mode off
offline:
	python3 tools/run_local.py --offline --xr-mode off
apk: import
	python3 tools/check_quest.py
	mkdir -p build
	touch build/.gdignore
	$(GODOT) --headless --xr-mode off --path . --export-debug "Meta Quest 3" build/naret-quest.apk
benchmark: import
	NARET_OFFLINE=1 $(GODOT) --xr-mode off --path . --script tools/benchmark.gd

# Regenerate the AED + heart props (Pillow and Blender required).
models:
	python3 tools/generate_aed_face.py
	/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/generate_models.py

# Live window: watch the chest cave in and recoil while it is driven.
cpr-live: import
	$(GODOT) --path . --xr-mode off --script tools/live_cpr.gd

# Palm menu alone, Quest renderer, fake hand: ARGS="--state cpr --pl --mic".
menu-shot: import
	$(GODOT) --path . --xr-mode off --script tools/capture_hand_menu.gd -- $(ARGS)

# Review loop against the Meta XR Simulator. macOS OpenXR needs the forward+
# renderer; the Quest build stays on gl_compatibility.
xr-shot: import
	$(GODOT) --path . --xr-mode on --rendering-method forward_plus \
		--rendering-driver vulkan --script tools/capture_xr.gd -- $(ARGS)

# Drehbuch scenario 1 recorded against the Meta XR Simulator (real hand input).
erc-video:
	timeout 1200 tools/record_xr_scenario.sh
