extends "res://tests/suite.gd"
## Step 3 (18 Nov 2026): a report that the person responds is corrected; "does not respond"
## in any wording is not taken for it.
const Main = preload("res://scripts/main.gd")

func run() -> Array[String]:
	failures.clear()
	for case in [["Die Person reagiert.", "de"], ["Er ist wach.", "de"], ["She responds.", "en"], ["He is awake", "en"], ["Osoba reaguje.", "pl"]]:
		check(Main._reports_responding(case[0], case[1]), "'%s' reports a response" % case[0])
	for case in [["Die Person reagiert nicht.", "de"], ["Er reagiert nicht", "de"], ["Keine Reaktion.", "de"], ["He is not responding.", "en"],
			["She doesn't respond", "en"], ["The person is unresponsive", "en"], ["Osoba nie reaguje.", "pl"], ["Hallo, hörst du mich? Öffne die Augen!", "de"]]:
		check(not Main._reports_responding(case[0], case[1]), "'%s' is no report of a response" % case[0])
	return failures
