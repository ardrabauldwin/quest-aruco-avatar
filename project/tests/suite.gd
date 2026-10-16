extends RefCounted
## Base for test_*.gd suites: collect failures, return them from run().

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
