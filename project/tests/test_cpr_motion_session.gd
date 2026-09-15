extends SceneTree
const Session = preload("res://cpr_motion_session.gd")
var failures := 0
var beats := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func stroke(session, hz := 72, amplitude := 0.055, bpm := 110.0) -> void:
	var frames := int(round(hz * 60.0 / bpm))
	session.update(0.0, true, 0.0)
	for i in range(1, frames + 1):
		var height := -amplitude * (1.0 - cos(TAU * float(i) / frames)) * 0.5
		session.update(1.0 / hz, true, height)

func run() -> void:
	for hz in [30, 72, 90]:
		var session = Session.new()
		for i in hz:
			session.update(1.0 / hz, true, 0.0)
		check(not session.active and session.count == 0, "Rest alone must not start CPR")
		stroke(session, hz)
		check(session.active and session.count == 1, "First complete stroke starts counting")
		stroke(session, hz)
		check(session.active and session.count == 2, "Two full strokes counted at %d Hz" % hz)
		for i in 28:
			stroke(session, hz)
		check(session.phase == "breathing" and session.count == 30, "30 strokes enter breathing phase")
		check(session.last_stroke_travel_m > 0.035, "Peak-to-top hand travel retained")
		var remaining: float = session.breathing_remaining_s
		session.update(1.0, false, 0.0, true)
		check(is_equal_approx(remaining, session.breathing_remaining_s), "App pause freezes breathing timer")
		session.update(2.0, false, 0.0)
		check(session.phase == "breathing" and session.breathing_remaining_s < remaining, "Breathing timer independent of hand availability")
		session.update(4.0, false, 0.0)
		check(session.phase == "compressions" and session.count == 0 and session.total_count == 30, "Next cycle resets count but preserves total")
		stroke(session, hz)
		check(session.count == 1, "Counting resumes after breathing")
	var jitter = Session.new()
	for i in 10:
		stroke(jitter, 72, 0.003)
	check(not jitter.active, "Small jitter must not count")
	jitter.start()
	jitter.update(0.016, true, 0.0)
	jitter.update(0.016, true, -0.03)
	jitter.update(0.016, false, 0.0)
	jitter.update(0.016, true, 0.0)
	check(jitter.count == 0, "Tracking gap cannot complete a stroke")
	stroke(jitter)
	check(jitter.count == 1, "Fresh complete stroke counts after tracking gap")
	var pacing = Session.new()
	pacing.start()
	pacing.beat_requested.connect(func(): beats += 1)
	for i in 720:
		pacing.update(1.0 / 72, false, 0.0)
	check(beats == 19, "110 BPM produces 19 paced beats in 10 seconds including initial beat")
	check(pacing.count == 0, "Metronome never creates compressions")
	# Simulated delta, deliberately unrelated to wall-clock time and beep phase.
	for bpm in [100.0, 110.0, 120.0]:
		for offset in [0.0, 0.15, 0.35, 0.50]:
			var offbeat = Session.new()
			offbeat._beat_remaining = offset
			for i in 12:
				stroke(offbeat, 90, 0.055, bpm)
			check(offbeat.count == 12, "No missed complete strokes at %s BPM / phase %s" % [bpm, offset])
	var slow = Session.new()
	stroke(slow)
	stroke(slow)
	check(slow.count == 2, "Slow-press test begins with two counts")
	stroke(slow, 72, 0.055, 50.0)
	check(slow.count == 3 and slow.feedback == "Press faster", "Slow complete stroke counts and shows pace feedback")
	for i in 360:
		slow.update(1.0 / 72, true, 0.0)
	check(slow.count == 3 and slow.total_count == 3, "Long tracked pause preserves counts")
	stroke(slow, 72, 0.055, 20.0)
	check(slow.count == 4, "Very slow complete stroke also counts")
	stroke(slow)
	check(slow.count == 5, "Normal stroke continues the existing count")
	stroke(slow)
	check(slow.count == 6 and slow.feedback == "Good timing", "Normal cadence clears slow feedback")
	for bpm in [90.0, 100.0, 110.0, 120.0, 150.0]:
		var speed = Session.new()
		for repetition in 6:
			stroke(speed, 300, 0.055, bpm)
		var expected := "Press faster" if bpm < 100.0 else ("Press slower" if bpm > 120.0 else "Good timing")
		check(speed.feedback == expected, "Correct speed message at %s BPM" % bpm)
		check(speed.count == 6, "Speed feedback never rejects counts")
		check(speed._bpm_samples.size() == 4, "Average contains four actual intervals")
	var first = Session.new()
	stroke(first)
	check(first._bpm_samples.is_empty() and first.feedback == "Measuring pace", "First press does not add startup delay to BPM")
	first.invalidate_tracking()
	stroke(first)
	check(first._bpm_samples.is_empty() and first.count == 2, "Timing restarts after tracking loss without resetting counts")
	# A short hand dropout (every 2-3 presses on the headset) must not wipe the measured pace;
	# only stopping does.
	var dropout = Session.new()
	for i in 6:
		stroke(dropout)
	dropout.update(0.016, false, 0.0)
	stroke(dropout)
	check(dropout._bpm_samples.size() == 4 and dropout.count == 7, "Pace window survives a tracking dropout (got %d samples)" % dropout._bpm_samples.size())
	check(dropout.last_interval_s == 0.0, "Press after a dropout adds no interval")
	for i in 300:
		dropout.update(1.0 / 72, true, 0.0)
	check(dropout._bpm_samples.is_empty(), "Pace window cleared after 3 s without a press")
	# A 1.8 s pause after a press is a stop, not a slow pace: it must not be averaged in.
	var paused = Session.new()
	for i in 4:
		stroke(paused)
	for i in 130:
		paused.update(1.0 / 72, true, 0.0)
	stroke(paused)
	check(paused._bpm_samples.is_empty() and paused.count == 5, "Press after a 1.8 s pause restarts the pace window (got %d samples)" % paused._bpm_samples.size())
	stroke(paused)
	check(paused._bpm_samples.size() == 1 and paused._bpm_samples[0] < 0.7, "Next press adds a real interval")
	# Dips under 2 cm are wobble, not compressions; 2.5 cm counts as a shallow press.
	var tiny = Session.new()
	for i in 5:
		stroke(tiny, 72, 0.015)
	check(tiny.count == 0, "1.5 cm dips must not count (got %d)" % tiny.count)
	stroke(tiny, 72, 0.025)
	check(tiny.count == 1 and tiny.last_stroke_quality == "shallow", "2.5 cm press counts as shallow")
	var lost = Session.new()
	stroke(lost)
	for i in 100:
		lost.update(1.0 / 72, false, 0.0)
	check(lost.count == 1, "Occlusion does not reset completed counts")
	stroke(lost)
	check(lost.count == 2, "New complete stroke counts after occlusion")
	var before := beats
	pacing.update(5.0, false, 0.0, true)
	check(beats == before, "No audio beats during application pause")
	pacing.phase = "breathing"
	pacing.breathing_remaining_s = 5.0
	pacing.update(1.0, false, 0.0)
	check(beats == before, "Metronome silent during breathing")
	# --- Regressions found by audit_cpr_motion_edges.gd ---
	# A first press that overshoots leaves _top above where the hands actually rest. Every
	# later press recoils to the real resting height, 20 mm below that top, and used to be
	# ignored forever ("the count stops").
	var drifted = Session.new()
	for height in [0.0, -0.02, -0.055, -0.02, -0.055, -0.02]:
		drifted.update(0.1, true, height)
	check(drifted.count == 2, "Presses recoiling 20 mm below the original top still count (got %d)" % drifted.count)
	check(absf(drifted.last_stroke_travel_m - 0.035) < 0.002, "Second drifted press measured from its own top")
	# Resting height creeping lower by 5 mm every press (leaning in) must not lose any press.
	var creep = Session.new()
	var base := 0.0
	for press in 9:
		var frames := int(round(72.0 * 60.0 / 110.0))
		for i in range(frames + 1):
			var dip := 0.055 * (1.0 - cos(TAU * float(i) / frames)) * 0.5
			creep.update(1.0 / 72.0, true, base - dip)
		base -= 0.005
	check(creep.count == 9, "Slowly sinking resting height keeps every press (got %d)" % creep.count)
	# A one-frame 55 mm tracking spike is not a compression.
	var spike = Session.new()
	for height in [0.0, -0.055, 0.0]:
		spike.update(1.0 / 72.0, true, height)
	check(spike.count == 0, "One-frame 55 mm spike must not count")
	for i in 20:
		spike.update(1.0 / 72.0, true, 0.0)
	stroke(spike)
	check(spike.count == 1, "Real press after a spike counts once")
	# A 5 mm upward wobble mid-descent is not a recoil; the press still counts exactly once.
	# (A dip that recoils to within 1 cm of the top is a legitimate shallow press and counts.)
	var wobble = Session.new()
	for height in [0.0, -0.01, -0.025, -0.02, -0.03, -0.04, -0.055, -0.04, -0.02, 0.0]:
		wobble.update(1.0 / 30.0, true, height)
	check(wobble.count == 1, "Mid-descent wobble does not split a press (got %d)" % wobble.count)
	check(absf(wobble.last_stroke_travel_m - 0.055) < 0.001, "Wobbled press keeps full excursion")
	print("CPR motion session tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
