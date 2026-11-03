extends SceneTree
## Replay a device hand trace (user://cpr_trace_<unix>.csv, written by cpr_hand_zone.gd) through
## cpr_motion_session.gd on the PC, so counter rules can be judged against real hand movement.
##   godot --headless --path . -s res://tools/replay_cpr_trace.gd -- <trace.csv> [min_count_excursion_m] [switch]
## switch: "reset" (device behaviour) clears the unfinished stroke when the palm changes;
## "join" shifts the new palm's heights so the signal continues where the old palm left off.
## Prints one line per counted press: "PRESS <trace t_ms> <travel_m>", then the total.
## tools/qcpr_replay_score.py scores these against a QCPR manikin recording.


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var source := FileAccess.open(args[0], FileAccess.READ)
	if source == null:
		printerr("cannot open ", args[0])
		quit(1)
		return
	var header := source.get_csv_line()
	var col := {}
	for i in range(header.size()):
		col[header[i]] = i
	var session = load("res://addons/naret_upstream/avatar/cpr_motion_session.gd").new()
	session.automatic_breathing_pause = false
	if args.size() > 1:
		session.min_count_excursion_m = float(args[1])
	var join := args.size() > 2 and args[2] == "join"
	var last_ms := -1
	var last_hand := ""
	var last_height := NAN
	var bias := 0.0
	var count := 0
	while not source.eof_reached():
		var row := source.get_csv_line()
		if row.size() < header.size():
			continue
		var ms := int(row[col["t_ms"]])
		var delta := 1.0 / 72.0 if last_ms < 0 else (ms - last_ms) / 1000.0
		last_ms = ms
		# The device clears the unfinished stroke whenever it changes palms (cpr_hand_zone.gd).
		var hand: String = row[col["hand"]]
		var valid: bool = row[col["valid"]] == "1"
		var raw := float(row[col["height_m"]])
		if hand != last_hand and last_hand != "":
			if join and valid and is_finite(last_height):
				bias = last_height - raw  # stacked palms sit cm apart: carry on from the old palm
			else:
				session.invalidate_tracking()
				bias = 0.0
		last_hand = hand
		var height := raw + bias
		if valid:
			last_height = height
		session.update(delta, valid, height, false)
		if session.total_count != count:
			count = session.total_count
			print("PRESS %d %.4f" % [ms, session.last_stroke_travel_m])
	print("TOTAL ", count)
	quit()
