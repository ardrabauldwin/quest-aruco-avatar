extends SceneTree
## Replays a headset CPR trace (user://cpr_trace_*.csv) through the shared two-hand
## press counter, so hand-selection rules can be checked on the PC against real hands.
##   godot --headless --xr-mode off --path . --script tools/replay_cpr_trace.gd -- --trace <file.csv>
## Prints the counted presses, the hand the counter followed over time, and the
## presses the headset counted at the time (count column) for comparison.

func _init() -> void:
	var path := ""
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--trace" and index + 1 < args.size():
			path = args[index + 1]
	if path.is_empty():
		push_error("usage: --trace <cpr_trace.csv>")
		quit(2)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("cannot open " + path)
		quit(2)
		return
	var header := file.get_csv_line()
	var column := {}
	for index in header.size():
		column[header[index]] = index
	for needed in ["t_ms", "count", "left_count_height_m", "right_count_height_m", "left_in_zone", "right_in_zone"]:
		if not column.has(needed):
			push_error("trace lacks column " + needed)
			quit(2)
			return
	var counter := NaretTwoHandPressCounter.new()
	var presses := [0]
	counter.pressed.connect(func(_depth: float): presses[0] += 1)
	var previous_t := -1
	var last_hand := ""
	var t0 := -1
	var device_count := 0
	var was_locked := false
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < header.size():
			continue
		var t := int(row[column.t_ms])
		if t0 < 0:
			t0 = t
		var delta := 0.014 if previous_t < 0 else clampf(float(t - previous_t) / 1000.0, 0.0, 0.05)
		previous_t = t
		var left := _hand(row, column, "left")
		var right := _hand(row, column, "right")
		counter.update(delta, left, right)
		device_count = int(row[column.count])
		if counter.calibration_locked != was_locked:
			was_locked = counter.calibration_locked
			print("t=%6.1fs calibration_locked=%s left_setup=%s right_setup=%s" % [float(t - t0) / 1000.0,
				was_locked, counter._counters.left.state, counter._counters.right.state])
		if counter.hand != last_hand:
			print("t=%6.1fs hand=%-5s state=%-7s replay=%d device=%d left=%.3f right=%.3f" % [
				float(t - t0) / 1000.0, counter.hand if not counter.hand.is_empty() else "none", counter.state,
				presses[0], device_count, float(left.height), float(right.height)])
			last_hand = counter.hand
	print("NARET_REPLAY presses=%d device_count=%d" % [presses[0], device_count])
	quit(0)

static func _hand(row: PackedStringArray, column: Dictionary, side: String) -> Dictionary:
	var text := row[column[side + "_count_height_m"]]
	var height := NAN if text == "nan" else float(text)
	return {"in_zone": row[column[side + "_in_zone"]] == "1", "height": height,
		"usable": is_finite(height), "source": "palm"}
