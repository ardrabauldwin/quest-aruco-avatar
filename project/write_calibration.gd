extends SceneTree
## Turns the offsets learned by make_calibration.py into a navel_calibration.cfg.
##
## Run headless:
##   godot --headless --script write_calibration.gd -- OFFSETS.json OLD.cfg NEW.cfg
##
## Godot writes a Transform3D as twelve bare numbers, and getting its basis convention wrong would
## transpose every rotation without any error being raised. So the file is built here, with Godot's
## own types doing the spelling, rather than by formatting text in Python and hoping.
##
## The existing file is loaded first and only the [common] offsets are replaced. That deliberately
## preserves [body] rest_basis: the offsets are rigid facts about markers glued to the mannequin,
## while the rest orientation describes where the mannequin is currently standing, and only the
## first kind can be learned from a recording made earlier.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Need OFFSETS.json OLD.cfg NEW.cfg")
		quit(1)
		return

	var text := FileAccess.get_file_as_string(args[0])
	if text.is_empty():
		push_error("Could not read %s" % args[0])
		quit(1)
		return
	var offsets: Dictionary = JSON.parse_string(text)

	var cfg := ConfigFile.new()
	# Not an error if it is missing - then this simply writes a fresh calibration with no rest.
	cfg.load(args[1])

	for node_name in offsets:
		var quaternion: Array = offsets[node_name]["quaternion"]
		var origin: Array = offsets[node_name]["origin"]
		cfg.set_value("common", node_name, Transform3D(
			Basis(Quaternion(quaternion[0], quaternion[1], quaternion[2], quaternion[3])),
			Vector3(origin[0], origin[1], origin[2])
		))
		print("%s  origin %.1f mm" % [
			node_name,
			Vector3(origin[0], origin[1], origin[2]).length() * 1000.0,
		])

	if cfg.save(args[2]) != OK:
		push_error("Could not write %s" % args[2])
		quit(1)
		return
	print("wrote ", args[2], "   rest_basis kept: ", cfg.has_section_key("body", "rest_basis"))
	quit()
