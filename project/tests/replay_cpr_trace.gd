extends SceneTree
## Replay a device hand trace (user://cpr_trace_<unix>.csv, written by cpr_hand_zone.gd) through
## cpr_motion_session.gd on the PC, so counter rules can be judged against real hand movement.
##   godot --headless --path project -s res://tests/replay_cpr_trace.gd -- <trace.csv> [min_count_excursion_m] [recoil_minimum_m]
## Prints every counted press with its time and travel, and the total.


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 1, "usage: -- <cpr_trace.csv> [min_count_excursion_m] [recoil_minimum_m]")
	var source := FileAccess.open(args[0], FileAccess.READ)
	assert(source != null, "cannot open " + args[0])
	var header := source.get_csv_line()
	var col := {}
	for i in range(header.size()):
		col[header[i]] = i
	var session = load("res://cpr_motion_session.gd").new()
	if args.size() > 1:
		session.min_count_excursion_m = float(args[1])
	if args.size() > 2:
		session.recoil_minimum_m = float(args[2])
	var last_ms := -1
	var t0 := -1
	var count := 0
	var counted: Array = []
	while not source.eof_reached():
		var row := source.get_csv_line()
		if row.size() < header.size():
			continue
		var ms := int(row[col["t_ms"]])
		if t0 < 0:
			t0 = ms
		var delta := 1.0 / 72.0 if last_ms < 0 else (ms - last_ms) / 1000.0
		last_ms = ms
		var valid := row[col["valid"]] == "1"
		var height := float(row[col["height_m"]])
		session.update(delta, valid, height, false)
		if session.total_count != count:
			count = session.total_count
			counted.append("#%d at %.2f s travel %.1f cm (%s)" % [count, (ms - t0) / 1000.0, session.last_stroke_travel_m * 100.0, session.last_stroke_quality])
	for line in counted:
		print(line)
	print("total counted: ", count)
	quit()
