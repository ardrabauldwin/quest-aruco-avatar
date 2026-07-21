class_name MarkerFreshness
extends RefCounted
## Tracks whether ArUco marker nodes are currently being detected, so a rig can hold its last good
## pose instead of drifting when a marker goes out of view.
##
## THE TRICK: main_3d.gd only writes a marker node's global_transform when that marker was found
## in the latest detection. Markers it did NOT find are simply not mentioned -- their nodes keep
## the previous pose, silently. So "this node's transform changed since last frame" is the same
## thing as "this marker was just detected". That means no timestamps, no signals, and no changes
## to main_3d.gd are needed.
##
## Three states, worst marker decides (a two-marker pose is only as good as its weaker half):
##   NOT_STARTED : the markers have never all been seen together -> keep the avatar hidden
##   TRACKING    : all markers fresh                             -> update the pose normally
##   FROZEN      : one or more markers lost                      -> hold the last good pose
##
## Once TRACKING has happened even once, this never returns NOT_STARTED again: losing a marker
## freezes the avatar where it was, it does not make it disappear. Detection also runs only
## ~every 100ms on the Quest, so brief gaps are normal and freezing rides straight over them.
##
## Freezing (rather than just letting the rig keep computing) matters when only ONE marker drops
## out: the other keeps moving, so an averaged pose would slide toward whichever marker is still
## tracked. Holding the last good pose avoids that.
##
## Usage:
##   var _freshness := MarkerFreshness.new(300)
##
##   func _process(_delta: float) -> void:
##       var state := _freshness.poll([head_marker, chest_marker])
##       visible = state != MarkerFreshness.State.NOT_STARTED
##       if state != MarkerFreshness.State.TRACKING:
##           return
##       ...place the avatar...
##
## CAVEAT: assumes a detected marker's pose always changes a little between detections. Camera
## noise makes that true in practice. If headset and marker were perfectly still AND solvePnP
## returned bit-identical numbers, this would read as FROZEN -- a harmless failure (the avatar
## simply holds still), not a dangerous one.

enum State {
	NOT_STARTED,   ## never yet seen all markers at once -- hide the avatar
	TRACKING,      ## all markers seen recently -- pose is trustworthy
	FROZEN,        ## a marker is missing -- hold the last good pose, do not update
}

## Treat a marker as lost once it has not moved for this long (ms). Detection lands roughly every
## 100ms, so this must tolerate a couple of misses. Raise it if the avatar freezes too eagerly.
var freeze_after_ms: int

# marker node -> the transform we last saw on it
var _last_xform := {}
# marker node -> Time.get_ticks_msec() when it last CHANGED (i.e. was last detected).
# Absent until the marker has moved at least once, which is how "never detected" is represented.
var _last_seen := {}
# Set once all markers have been fresh simultaneously. From then on a loss means FROZEN, never
# NOT_STARTED -- the avatar has been placed and should stay put rather than vanish.
var _started := false

const _NEVER := 1 << 30   # stand-in for "infinitely stale"; larger than any real age in ms


func _init(p_freeze_after_ms := 300) -> void:
	freeze_after_ms = p_freeze_after_ms


## Milliseconds since this marker last moved, i.e. since it was last detected. Returns a huge
## number if it has never been detected. Call at most once per frame per marker -- this updates
## the internal record.
func age_ms(marker: Node3D) -> int:
	if marker == null:
		return _NEVER

	var now := Time.get_ticks_msec()
	var x := marker.global_transform

	if not _last_xform.has(marker):
		# First sighting: nothing to compare against yet, so we cannot claim it is being tracked.
		_last_xform[marker] = x
		return _NEVER

	if x != _last_xform[marker]:
		_last_xform[marker] = x
		_last_seen[marker] = now

	if not _last_seen.has(marker):
		return _NEVER   # present since startup but never moved -- never detected

	return now - _last_seen[marker]


## Feed every marker the pose depends on. Returns the state of the WORST one -- all must be
## tracked for an averaged pose to mean anything. Call exactly once per frame; it advances the
## internal record, so calling it twice in a frame makes the second call read as stale.
func poll(markers: Array) -> State:
	var worst := 0
	for m in markers:
		worst = maxi(worst, age_ms(m as Node3D))

	if worst <= freeze_after_ms:
		_started = true
		return State.TRACKING

	return State.FROZEN if _started else State.NOT_STARTED


## True once all markers have been detected together at least once.
func has_started() -> bool:
	return _started


## Forget everything. Next poll() reports NOT_STARTED until the markers are seen moving again.
func reset() -> void:
	_last_xform.clear()
	_last_seen.clear()
	_started = false
