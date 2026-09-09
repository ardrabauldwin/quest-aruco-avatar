extends SceneTree
## Diagnostic audit: print observed edge behavior without changing runtime rules.
const Session = preload("res://cpr_motion_session.gd")

func _init() -> void:
	call_deferred("run")

func cycles(session, hz: int, amplitude: float, number := 8) -> void:
	var frames := int(round(hz * 60.0 / 110.0))
	for cycle in number:
		for i in range(frames + 1):
			var height := -amplitude * (1.0 - cos(TAU * float(i) / frames)) * 0.5
			session.update(1.0 / hz, true, height)

func run() -> void:
	for hz in [30, 72, 90]:
		for amplitude in [0.040, 0.050, 0.055]:
			var session = Session.new()
			cycles(session, hz, amplitude)
			print("AUDIT 8 cycles, ", hz, " Hz, ", amplitude * 1000.0, " mm: ", session.count, " counted")
	var spike = Session.new()
	for height in [0.0, -0.055, 0.0]:
		spike.update(1.0 / 72.0, true, height)
	print("AUDIT one-frame 55 mm tracking spike: ", spike.count, " counted")
	var gap = Session.new()
	for height in [0.0, -0.02, -0.055]:
		gap.update(1.0 / 72.0, true, height)
	gap.update(1.0 / 72.0, false, 0.0)
	gap.update(1.0 / 72.0, true, 0.0)
	print("AUDIT full excursion with one missing frame before recoil: ", gap.count, " counted")
	var recoil = Session.new()
	for height in [0.0, -0.02, -0.055, -0.02, -0.055, -0.02]:
		recoil.update(0.1, true, height)
	print("AUDIT two presses ending 20 mm below starting top: ", recoil.count, " counted")
	for bpm in [90.0, 150.0]:
		var paced = Session.new()
		var frames := int(round(72.0 * 60.0 / bpm))
		for cycle in 8:
			for i in range(frames + 1):
				paced.update(1.0 / 72.0, true, -0.055 * (1.0 - cos(TAU * float(i) / frames)) * 0.5)
		print("AUDIT ", bpm, " BPM: ", paced.count, " counted; feedback: ", paced.feedback)
	var shallow = Session.new()
	cycles(shallow, 72, 0.055, 1)
	cycles(shallow, 72, 0.040, 1)
	print("AUDIT 55 mm then 40 mm press: count ", shallow.count, "; saved travel still ", shallow.last_stroke_travel_m * 1000.0, " mm")
	quit()
