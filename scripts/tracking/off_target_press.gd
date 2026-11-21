extends RefCounted
## Pressing beside the green box (12 Nov 2026): a palm on the chest, outside the contact
## slab, bobbing up and down. Today such presses count nothing and nothing is said; the
## trainee presses into silence. This only detects; the app speaks the correction once.
## Coordinates are mannequin-local metres with the sternum at the origin, +Y up.
## Loaded by preload (no class_name): the headless test runner has no global class cache.

## A palm this close to the compression point (flat distance) and at chest height counts
## as "on the chest". The sternum is the highest point; the belly and the sides lie lower.
const NEAR_M := 0.25
const BELOW_M := 0.08
const ABOVE_M := 0.06
## Vertical travel within the window that counts as pressing.
const WINDOW_S := 1.0
const TRAVEL_M := 0.02
## After a detection, the next one is reported no sooner than this.
const COOLDOWN_S := 15.0

var _clock := 0.0
var _last_report := -1.0e9
var _history: Array = [[], []]  # per hand: [time, height] while on the chest

static func on_chest(local: Vector3) -> bool:
	return Vector2(local.x, local.z).length() <= NEAR_M and local.y >= -BELOW_M and local.y <= ABOVE_M

func reset() -> void:
	_clock = 0.0
	_last_report = -1.0e9
	_history = [[], []]

func observe(palms: Array, on_target: bool, delta: float) -> bool:
	## `palms`: per hand a mannequin-local Vector3 or null. `on_target`: the hand zone
	## reports a heel on the green box, which makes any bobbing a proper press.
	## Returns true when an off-target press is detected (at most once per COOLDOWN_S).
	_clock += clampf(delta, 0.0, 0.05)
	var detected := false
	for hand in mini(palms.size(), 2):
		var palm: Variant = palms[hand]
		if on_target or not (palm is Vector3) or not on_chest(palm):
			_history[hand] = []
			continue
		_history[hand].append([_clock, (palm as Vector3).y])
		while not _history[hand].is_empty() and float(_history[hand][0][0]) < _clock - WINDOW_S:
			_history[hand].pop_front()
		var low := INF
		var high := -INF
		for sample in _history[hand]:
			low = minf(low, float(sample[1]))
			high = maxf(high, float(sample[1]))
		if high - low >= TRAVEL_M and _clock - _last_report >= COOLDOWN_S:
			_last_report = _clock
			detected = true
	return detected
