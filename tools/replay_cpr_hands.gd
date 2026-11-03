extends SceneTree
## Replay a two-palm device trace (cpr_hand_zone.gd, with unix_ms/left_height_m/right_height_m)
## through cpr_motion_session.gd with a chosen hand rule, to compare rules against a QCPR manikin.
##   godot --headless --path . -s res://tools/replay_cpr_hands.gd -- <trace.csv> <rule> [contact|-] [min_count_excursion_m]
## rule: device (the recorded choice), both (mean of the tracked palms), upper (higher palm),
##       left, right, mover (the palm whose robust recent travel is clearly larger),
##       lock (mover for the first LOCK_AFTER_PRESSES presses after a pause, then stay on that palm unless it is lost for LOCK_LOST_S). "contact" also requires the recorded contact_armed flag.
## When the palms in use change, the signal is shifted to continue where it was, so the few cm
## between stacked palms never read as travel. Prints "PRESS <unix_ms> <travel_m>" per press.


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var source := FileAccess.open(args[0], FileAccess.READ)
	if source == null:
		printerr("cannot open ", args[0])
		quit(1)
		return
	var rule: String = args[1] if args.size() > 1 else "device"
	var use_contact := args.size() > 2 and args[2] == "contact"
	var excursion: float = float(args[3]) if args.size() > 3 else NAN
	var header := source.get_csv_line()
	var col := {}
	for i in range(header.size()):
		col[header[i]] = i
	var session = load("res://addons/naret_upstream/avatar/cpr_motion_session.gd").new()
	session.automatic_breathing_pause = false
	if is_finite(excursion):
		session.min_count_excursion_m = excursion
	var last_ms := -1
	var last_source := ""
	var last_signal := NAN
	var bias := 0.0
	var count := 0
	var history := {"left": [], "right": []}   # [t_s, height] over MOVER_WINDOW_S
	var mover := ""
	var mover_wait := 0.0
	var t_s := 0.0
	var lost_s := 0.0
	var series_start := 0      # total_count when the current series began
	var quiet_s := 0.0         # time since the last counted press
	while not source.eof_reached():
		var row := source.get_csv_line()
		if row.size() < header.size():
			continue
		var ms := int(row[col["t_ms"]])
		var delta := 1.0 / 72.0 if last_ms < 0 else (ms - last_ms) / 1000.0
		last_ms = ms
		var left := float(row[col["left_height_m"]])
		var right := float(row[col["right_height_m"]])
		var raw := NAN
		var used := ""
		t_s += delta
		for side in ["left", "right"]:
			var h := left if side == "left" else right
			if is_finite(h):
				history[side].append([t_s, h])
			while not history[side].is_empty() and float(history[side][0][0]) < t_s - MOVER_WINDOW_S:
				history[side].pop_front()
		match rule:
			"lock":
				quiet_s += delta
				if quiet_s > LOCK_PAUSE_S:
					series_start = session.total_count  # a pause: decide the hand afresh
				var lm := _robust_range(history.left)
				var rm := _robust_range(history.right)
				var have := is_finite(left if mover == "left" else right)
				lost_s = 0.0 if have else lost_s + delta
				if mover == "" or (session.total_count - series_start < LOCK_AFTER_PRESSES and (rm if mover == "left" else lm) > (lm if mover == "left" else rm) * MOVER_RATIO + MOVER_MARGIN_M) or lost_s > LOCK_LOST_S:
					var pick := "left" if (lm >= rm and is_finite(left)) or not is_finite(right) else "right"
					if pick != mover:
						print("SWITCH %s %s left_range=%.3f right_range=%.3f lost=%.2f presses=%d" % [row[col["unix_ms"]], pick, lm, rm, lost_s, session.total_count])
						mover = pick
						lost_s = 0.0
				raw = left if mover == "left" else right
				used = mover if is_finite(raw) else ""
			"mover":
				var lm := _robust_range(history.left)
				var rm := _robust_range(history.right)
				var mine := lm if mover == "left" else rm
				var theirs := rm if mover == "left" else lm
				if mover == "" or not is_finite(left if mover == "left" else right):
					mover = "left" if (lm >= rm and is_finite(left)) or not is_finite(right) else "right"
					mover_wait = 0.0
				elif theirs > mine * MOVER_RATIO + MOVER_MARGIN_M:
					mover_wait += delta
					if mover_wait >= MOVER_DWELL_S:
						mover = "right" if mover == "left" else "left"
						mover_wait = 0.0
				else:
					mover_wait = 0.0
				raw = left if mover == "left" else right
				used = mover if is_finite(raw) else ""
			"device":
				if row[col["valid"]] == "1":
					raw = float(row[col["height_m"]])
					used = row[col["hand"]]
			"both":
				if is_finite(left) and is_finite(right):
					raw = (left + right) * 0.5
					used = "both"
				elif is_finite(left):
					raw = left
					used = "left"
				elif is_finite(right):
					raw = right
					used = "right"
			"upper":
				if is_finite(left) and (not is_finite(right) or left >= right):
					raw = left
					used = "left"
				elif is_finite(right):
					raw = right
					used = "right"
			"left":
				raw = left
				used = "left" if is_finite(left) else ""
			"right":
				raw = right
				used = "right" if is_finite(right) else ""
		var valid := is_finite(raw) and (not use_contact or row[col["contact_armed"]] == "1")
		if valid and used != last_source:
			if rule == "device" and last_source != "":
				session.invalidate_tracking()  # what the headset does on a palm change
				bias = 0.0
			elif is_finite(last_signal):
				bias = last_signal - raw
			last_source = used
		var height := raw + bias if valid else 0.0
		if valid:
			last_signal = height
		session.update(delta, valid, height, false)
		if session.total_count != count:
			count = session.total_count
			quiet_s = 0.0
			print("PRESS %s %.4f" % [row[col["unix_ms"]], session.last_stroke_travel_m])
	print("TOTAL ", count)
	quit()


const MOVER_WINDOW_S := 1.5
const MOVER_RATIO := 1.3
const MOVER_MARGIN_M := 0.005
const MOVER_DWELL_S := 0.2
const LOCK_LOST_S := 1.0
const LOCK_AFTER_PRESSES := 3
const LOCK_PAUSE_S := 3.0


## Spread of a palm's heights over the window without its two most extreme readings at each end:
## the hidden lower palm jumps 10+ cm for single frames, which a plain max-min reads as movement.
func _robust_range(samples: Array) -> float:
	if samples.size() < 10:
		return 0.0
	var heights: Array[float] = []
	for entry in samples:
		heights.append(float(entry[1]))
	heights.sort()
	var cut := maxi(2, heights.size() / 10)
	return heights[heights.size() - 1 - cut] - heights[cut]
