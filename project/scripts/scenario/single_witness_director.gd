extends NaretBystanderDirector
## One speaking witness. Never generates compressions or AED actions.

func advance(delta: float) -> void:
	_t += delta
	if scenario and scenario.state == NaretScenario.State.INTRO and _t - _state_t > URGE_AFTER_S:
		_say_once("anna_urge")

func _on_state_changed(state: int) -> void:
	_state_t = _t
	if state in [NaretScenario.State.IDLE, NaretScenario.State.INTRO]:
		_reset()
		scenario.aed_available = false
	if state == NaretScenario.State.INTRO:
		_say("anna_arrive", 0.0)

func _on_event(event: Dictionary) -> void:
	pass # Witness facts are answers to questions, not automatic assessment chatter.

func on_stroke(_correct_position: bool) -> void:
	pass

func on_intent(_intent: String) -> void:
	pass
