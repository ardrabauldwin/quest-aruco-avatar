extends "res://tests/suite.gd"

const EKG = preload("res://scripts/ekg/ekg_system.gd")
var beats := 0

func run() -> Array[String]:
	var ekg := EKG.new()
	ekg.beat.connect(func(): beats += 1)
	ekg.set_rhythm(EKG.Rhythm.SINUS, 60.0)
	check(ekg.sample(0.25) > 0.95, "Sinus R peak at quarter cycle")
	check(absf(ekg.sample(0.25) - ekg.sample(1.25)) < 0.00001, "Sinus waveform period follows heart rate")
	ekg.advance(0.24)
	check(beats == 0, "No mechanical beat before ECG R peak")
	ekg.advance(0.01)
	check(beats == 1, "Mechanical beat synchronized with R peak")
	ekg.advance(1.0)
	check(beats == 2, "One beat per cycle")
	for rhythm in range(5):
		ekg.set_rhythm(rhythm)
		for index in range(720):
			var value := ekg.sample(float(index) / 72.0)
			check(is_finite(value) and absf(value) < 2.0, "Bounded finite trace rhythm %d at sample %d" % [rhythm, index])
		if rhythm != EKG.Rhythm.SINUS:
			var before := beats
			ekg.advance(10.0)
			check(beats == before and not ekg.has_mechanical_pulse(), "Pulseless rhythm %d has no mechanical heartbeat" % rhythm)
	ekg.set_rhythm(EKG.Rhythm.ASYSTOLE)
	check(ekg.sample(1.234) == 0.0 and ekg.bpm == 0.0, "Asystole has no artificial pulse")
	ekg.set_rhythm(EKG.Rhythm.PEA, 75.0)
	check(ekg.sample(0.2) > 0.95, "PEA still has organized electrical activity")
	ekg.set_rhythm(EKG.Rhythm.SINUS, 200.0)
	check(not ekg.alarm.is_empty(), "Out-of-range sinus rate raises simulation alarm")
	ekg.set_rhythm(EKG.Rhythm.SINUS, 75.0)
	check(ekg.alarm.is_empty(), "Normal sinus rate clears alarm")
	ekg.set_rhythm(999)
	check(ekg.rhythm == EKG.Rhythm.SINUS, "Invalid rhythm cannot corrupt state")
	check(ekg.sample(NAN) == 0.0, "Nonfinite sample time is safe")
	ekg.free()
	return failures
