extends "res://tests/suite.gd"
## One cloud request per utterance (11 Nov 2026): unresolved meaning ends in a clarification
## and never in a second "repair" request or a guessed step.
const Interpreter = preload("res://scripts/ai/speech_pipeline.gd")
class FakeAPI extends NaretUniAPIClient:
	var replies: Array = []
	var calls := 0
	func is_available(_model: String = "") -> bool: return true
	func complete(_messages: Array) -> Dictionary:
		calls += 1
		return replies.pop_front()
func reply(data: Dictionary) -> Dictionary:
	return {"ok":true,"json":{"choices":[{"message":{"content":JSON.stringify(data)}}]}}
func run() -> Array[String]:
	failures.clear()
	var api := FakeAPI.new()
	var interpreter := Interpreter.new()
	interpreter.configure(api)
	var actions: Array = []
	var clarifications: Array = []
	interpreter.observation_ready.connect(func(a): actions.append(a))
	interpreter.clarification.connect(func(t): clarifications.append(t))
	var original := "I have given one rescue bread."
	api.replies = [reply({"action":"none","kind":"uncertain","result":"none","evidence":original})]
	await interpreter.interpret(original,"en","state-A")
	check(api.calls == 1 and clarifications.size() == 1 and actions.is_empty(), "unresolved meaning: one request, a clarification, no guessed step")
	check(interpreter.last_doubtful, "an uncertain answer is a doubt, so main asks the yes/no question")
	api.replies = [reply({"action":"check_breathing","kind":"report","result":"normal","evidence":"He breathes normally"})]
	await interpreter.interpret("He breathes normally","en","state-A")
	check(api.calls == 2 and actions.is_empty() and not interpreter.last_doubtful, "a clear opposite finding is not a doubt and not a step")
	api.replies = [{"ok":false}]
	await interpreter.interpret(original,"en","state-A")
	check(api.calls == 3 and clarifications.size() == 3, "service failure ends in a clarification, no retry")
	api.replies = [reply({"action":"check_breathing","kind":"report","result":"abnormal","evidence":"He is not breathing"})]
	await interpreter.interpret("He is not breathing at all, really","en","state-A")
	check(actions == ["check_breathing"], "a clear report is accepted as a reported step")
	interpreter.free()
	api.free()
	return failures
