extends "res://tests/suite.gd"
const Coach = preload("res://scripts/ai/training_coach.gd")
const Dialogue = preload("res://scripts/ai/llm_orchestrator.gd")

func run() -> Array[String]:
	for question in ["Anna, does your husband have diabetes?", "Does he have any illnesses", "Instructor, does he have a heart disease?", "Anna, hat Ihr Mann Vorerkrankungen?", "Hat er Diabetes", "Instruktor, czy pacjent ma cukrzycę?", "Anno, czy on ma jakieś choroby?", "Does he have breathing-related medical conditions?"]:
		check(Coach.asks_patient_history(question) and Coach.asks_witness(question),"patient history goes to Anna: "+question)
		check(not Coach.asks_for_help(question),"instructor does not answer Anna's history question: "+question)
	for request in ["Anna, please call 112.", "Anna, could you call 112?", "Anna, ruf bitte die 112 an.", "Anno, zadzwoń proszę pod 112."]:
		check(not Coach.asks_witness(request) and not Coach.asks_for_help(request),"emergency request stays in observation path: "+request)
	for question in ["Instructor, how deep should I press?", "What should I do if he has diabetes?", "Wie soll ich drücken?", "Co mam teraz zrobić?"]:
		check(Coach.asks_for_help(question) and not Coach.asks_patient_history(question),"technique remains instructor guidance: "+question)
	check(Coach.asks_witness("Anna, are you his wife?"),"explicitly named Anna can answer other background questions")
	check(not Coach.asks_witness("He is not responding."),"finding is not witness conversation")
	var scenario := NaretScenario.new()
	var context := Coach.context(scenario,"en")
	check("no known diagnosed medical conditions" in context.patient_facts,"fictional no-known-illness profile is supplied")
	check("medication, allergies" in context.patient_facts and "unspecified" in context.patient_facts,"unknown facts remain unspecified")
	for language in ["en","de","pl"]:
		var fallback := Dialogue.patient_history_fallback("Does he have diabetes?",language)
		check(fallback.action=="none" and fallback.language==language and not fallback.text.is_empty(),"history fallback has no progression action: "+language)
		var unknown := Dialogue.patient_history_fallback("What medication does he take?",language)
		check(unknown.text!=fallback.text and unknown.action=="none","medication fallback does not invent a prescription: "+language)
		context.speaker="bystander"
		var messages := Dialogue.build_messages("Does he have diabetes?",context,language)
		check("patient_facts" in str(messages[1].content),"free dialogue receives profile: "+language)
		check(Dialogue.witness_fact_reply("Does he have diabetes?",language).is_empty(),"medical-history wording is not forced through fixed incident line: "+language)
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	for label in ["University cloud connected","Reply from university cloud","Uni-Cloud","chmury uczelni"]:
		check(not label in source,"trainee UI does not identify university provider: "+label)
	scenario.free()
	return failures
