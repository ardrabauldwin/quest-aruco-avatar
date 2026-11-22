class_name NaretSetupFlow
extends RefCounted
## The trainee's choices before the scenario (issue #1, 0. App-Start). Since 18 Nov 2026 they
## are made with the wrist's fold-out keys (Sprache, Modus, Situation, Beatmung, Geschlecht),
## preset at the welcome; no questions are asked one by one any more.
##   language: "de" | "pl" | "en"      mode: "own" | "neighbour"
##   situation: "A" | "B"              breaths: "yes" | "no"      gender: "male" | "female" | "other"
var answers := {}

## The choices are set (the welcome presets them): "Start training" may use them.
func done() -> bool:
	return answers.has("situation")
