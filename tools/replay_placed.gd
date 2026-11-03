extends SceneTree
## Replay a placed-counting trace (cpr_hand_zone.gd placed_counting, with the measuring-point
## columns) through scripts/tracking/placed_press_counter.gd with another hand rule or point.
##   godot --headless --path . -s res://tools/replay_placed.gd -- <trace.csv> <rule> <point>
## rule: two | smooth | higher | seen | left | right.  point: heel | palm | wrist | knuckles | full.
## Prints "PRESS <unix_ms> <depth_m>" per counted press and "PLACED <unix_ms> <hand>".


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var source := FileAccess.open(args[0], FileAccess.READ)
	if source == null:
		printerr("cannot open ", args[0])
		quit(1)
		return
	var rule: String = args[1] if args.size() > 1 else "higher"
	var point: String = args[2] if args.size() > 2 else "heel"
	var header := source.get_csv_line()
	var col := {}
	for i in range(header.size()):
		col[header[i]] = i
	var counter
	if rule == "two":
		counter = NaretTwoHandPressCounter.new()  # both palms counted, the steadier one reported
	else:
		counter = NaretPlacedPressCounter.new()
		counter.hand_rule = rule
	var now := [0]
	counter.pressed.connect(func(depth: float): print("PRESS %d %.4f" % [now[0], depth]))
	counter.placed.connect(func(hand: String, _rest: float): print("PLACED %d %s" % [now[0], hand]))
	var last_ms := -1
	while not source.eof_reached():
		var row := source.get_csv_line()
		if row.size() < header.size() or row[col["placed_state"]] == "":
			continue
		var ms := int(row[col["t_ms"]])
		var delta := 1.0 / 72.0 if last_ms < 0 else clampf((ms - last_ms) / 1000.0, 0.0, 0.25)
		last_ms = ms
		now[0] = int(row[col["unix_ms"]])
		var hands := []
		for side in ["left", "right"]:
			var key: String = side + ("_heel_m" if point == "heel" else "_" + point + "_m")
			# Traces before the measuring-point columns (2026-11-03 15:33) carry only the heel.
			var seen_col: int = col.get(side + "_seen_joints", -1)
			hands.append({"in_zone": row[col[side + "_in_zone"]] == "1",
				"height": float(row[col[key]]) if col.has(key) else NAN,
				"seen": int(row[seen_col]) if seen_col >= 0 else 0})
		counter.update(delta, hands[0], hands[1])
	quit()
