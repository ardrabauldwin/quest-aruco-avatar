extends "res://tests/suite.gd"
## The signs over the AED: in the trainee's language from the start, drawn as cards.

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var scenario := NaretScenario.new()
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	var model: Node3D = load("res://assets/models/aed.glb").instantiate()
	var device := NaretAED.new()
	var world := Node3D.new()
	tree.root.add_child(world)
	world.add_child(model)
	for node in [scenario, patient, device]: tree.root.add_child(node)
	device.configure(model, patient)
	scenario.start()
	# 14 Nov 2026: English chosen, the device switched on before it had said anything,
	# and the sign read "AED AN".
	device.sync(scenario, "en")
	device._power_on()
	check(not device._on_card.is_empty() and (device._on_card.label as Label).text == "AED ON", "switched on before it speaks, the sign is in the chosen language (%s)" % ("" if device._on_card.is_empty() else (device._on_card.label as Label).text))
	check((device._on_card.sprite as Sprite3D).visible, "the ON card is shown while the device is on")
	device.sync(scenario, "pl")
	check((device._on_card.label as Label).text == "AED WŁĄCZONY", "a language change while it is on changes the sign")
	var short := (device._on_card.view as SubViewport).size.x
	device.sync(scenario, "en")
	check((device._on_card.view as SubViewport).size.x < short, "the card is as wide as its text")
	check(device._on_until > Time.get_ticks_msec() / 1000.0 and device._on_until <= Time.get_ticks_msec() / 1000.0 + NaretAED.ON_SIGN_S + 0.1, "a language change does not restart the sign's time")
	device._on_until = 0.0
	device._process(0.02)
	check(not (device._on_card.sprite as Sprite3D).visible, "the ON sign goes away after its time")
	device._show_shock_sign(true)
	check((device._shock_card.label as Label).text == "SHOCK DELIVERED" and (device._shock_card.sprite as Sprite3D).visible, "the shock card uses the same builder")
	device._show_on(false)
	device._show_shock_sign(false)
	check(not (device._on_card.sprite as Sprite3D).visible and not (device._shock_card.sprite as Sprite3D).visible, "both cards can be hidden")
	for node in [scenario, patient, device, world]: node.queue_free()
	return failures
