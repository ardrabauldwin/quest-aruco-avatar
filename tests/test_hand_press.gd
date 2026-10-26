extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	# Contact rule: near the compression point and not hovering above the chest.
	var sternum := Vector3(0.0, 0.20, -0.1)
	check(NaretXRInteraction.press_contact(sternum + Vector3(0.03, -0.02, 0.02), sternum) != null, "a heel on the chest counts")
	check(NaretXRInteraction.press_contact(sternum + Vector3(0.15, -0.02, 0.0), sternum) == null, "a hand beside the chest does not")
	check(NaretXRInteraction.press_contact(sternum + Vector3(0.0, 0.05, 0.0), sternum) == null, "a hand hovering above the chest does not")
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	tree.root.add_child(patient)
	await tree.process_frame
	patient.set_process(false)
	var rest := patient.sternum.global_position
	var ring_rest := patient.zone.position.y
	patient.set_hand_press(rest - Vector3(0, 0.03, 0))
	patient._step_press(1.0)
	check(absf(patient._press_depth - 0.03) < 0.001, "the chest follows a hand 3 cm below its rest, got %s" % patient._press_depth)
	check(absf(patient.zone.position.y - (ring_rest - 0.03)) < 0.001, "the ring sinks with the hand")
	# Faulty tracking far below the chest is bounded, and a jump is smoothed.
	patient.set_hand_press(rest - Vector3(0, 0.5, 0))
	patient._step_press(0.011)
	check(patient._press_depth < PRESS_MAX(), "a sudden jump is smoothed, got %s" % patient._press_depth)
	patient._step_press(1.0)
	check(is_equal_approx(patient._press_depth, NaretMannequin.PRESS_MAX_DEPTH_M), "depth is capped at %s m" % NaretMannequin.PRESS_MAX_DEPTH_M)
	patient.release_hand_press()
	patient._step_press(1.0)
	check(patient._press_depth == 0.0 and not patient._press_active, "letting go springs the chest back")
	check(is_equal_approx(patient.zone.position.y, ring_rest), "the ring returns to rest")
	patient.free()
	return failures

func PRESS_MAX() -> float:
	return NaretMannequin.PRESS_MAX_DEPTH_M
