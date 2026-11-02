extends Node
## Runs after rig animation (100) and floor grounding (110), before rendering.
var validate: Callable

func _ready() -> void:
	process_priority = 200

func _process(_delta: float) -> void:
	if validate.is_valid(): validate.call()
