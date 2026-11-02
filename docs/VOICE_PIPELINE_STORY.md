# The VR voice pipeline: current local source

This describes the local source, not a confirmed installed headset build. No
Whisper weights were changed. Start with the patient placed, training started
and the microphone on. Recognition and confirmation use the trainee's chosen
English/German/Polish language, even when Anna speaks the neighbour language.

## 1. Microphone and WAV

Audio RMS above 0.02 starts recording. Up to 0.35 s of earlier audio is retained.
More than 1.2 s of below-threshold sound ends the recording after speech has
started. Above-threshold sound resets that silence timer. The redundant 0.5 s
recording-age gate was removed. The current source has no duration cap
(MAX_RECORDING_SECONDS=0); silence, microphone-off, focus loss or reset end it. Under 100 ms or less than 3200 bytes of capture is rejected.

Automatic activation pauses while reply audio is being prepared/played, while
transcription is pending, or when input focus is lost. Speaking over the
instructor is therefore not reliable barge-in in this mode. Godot builds a
PCM16 WAV in memory, preserving captured sample rate/channels. This capture
path does not automatically save a WAV file.

## 2. Transcription

The request sends WAV, selected language, configured model and vocabulary prompt.
Vocabulary is general terminology, identical across stages, not the expected
answer. It does not repair missing audio or guarantee correct recognition.

Default university base: https://apphubai.wolke.uni-greifswald.de/v1;
requested ASR model: large-v3. A configured loopback ASR endpoint
http://127.0.0.1:8767/inference instead selects the PC route. Its server decides
the actual loaded Whisper model; a PC connection is not inference on Quest.
The local GPU handler forwards prompt as initial_prompt (limit 512 characters).
AppHub prompt handling and recognition improvement still need live verification.

## 3. Interpret the text

The real main.gd routing has shortcuts: explicit two-breath reports first,
then help questions and Anna questions. Other sentences enter the selected-
language confirmation handler. Pending yes/no answers are handled there.
Exact phrases and whole-report grammar are tried before fuzzy proposals.
Recognised reports go to CCBM. If unhandled, the CCBM phrase route is tried,
then unknown wording goes to the LLM interpreter. These are early returns,
not four model calls on every report.

Exact matching checks whole phrases after normalising case/punctuation/spaces.
The flexible grammar accepts selected subjects, verbs and filler words; it is
not an arbitrary bag of keywords. Saying 30 compressions never creates strokes.

## 4. Fuzzy confirmation

Minimum similarity 0.80; minimum lead over the next report class 0.08. These are
manual cutoffs, not probabilities or learned optima. Generic candidates must
have equal word counts and one changed word, preserving negation/count tokens.
Questions, known opposite findings and future/compound markers are excluded.
All report classes are scored before checking available actions, so the stage
does not boost an unrelated sentence. Older English aliases such as 'scene a
save' remain as exceptions handled by explicit confirmation rules.

Every fuzzy proposal requires confirmation, even at a high score. One/two breaths
have distinct questions. Pending proposals expire after 30 s, clear on context
or language change, can be consumed once and still require the action to be
allowed. Selected 'I think', 'Ich glaube', 'Myślę, że' reports also ask first.
There are 18 exact-text offline Piper clips: five questions and one retry in
each language. These questions need no live TTS request.

## 5. LLM fallback

The model gets a classification instruction and up to 1000 characters of the
utterance, treated as data. It is told not to infer an action from scenario
order. Example input: 'I checked him and got no reaction.' Example output:

```json
{"action":"check_responsiveness","kind":"report","result":"unresponsive","evidence":"got no reaction"}
```

This is a text LLM, not Whisper. Qwen plus LoRA applies only if that serving
configuration is active. The cloud default identifier in the source is
unsloth/Qwen3.8-27B-GGUF:Q4_K_M; this string does not verify that such a model is
available or deployed. A configured local AI endpoint takes precedence. There
is no automatic cloud failover after local AI failure. Overrides come from
user://config.json.

Cloud completion settings: temperature 0.3, max_tokens 160, stream=false,
enable_thinking=false. Local server decoding settings are separate.
Reject malformed JSON, output over 4096 characters, unknown labels, wrong
types and evidence absent from the input. Accepted findings must match an
allowed action/result combination. Questions, intentions and opposite findings
do not become negative clinical findings. This interpreter supports one completed
breath; explicit two-breath reports use the separate pair handler. Valid JSON
and verbatim evidence do not prove correct meaning or physical performance.
Failures ask clarification.

## 6. CCBM, progression and response

The CCBM bridge checks available actions, sends structural observation history
and the new candidate to the bundled native engine on Quest (external worker
on desktop), and validates the response. Quest inference runs off the render
thread with no PC or CCBM HTTP dependency.
Required: engine=ccbm, same action, finite probability >=0.90 and <=1.0. It
rechecks allowed actions after the response. This 0.90 policy is a prototype
cutoff, not a measured accuracy. Service failure cannot become a successful step.

scenario_controller.gd stores state/counters. Physical detected strokes count
compressions. Spoken reports describe findings and breaths. In the selected
30:2 exercise, completing the compression count enables ventilation; two
accepted breath reports return to compressions. The configured stop/handover
ends the loop. This describes application progression, not verified physical CPR.
d.pddl defines model actions/conditions/effects; p.pddl initial facts/goal.
The external worker and Godot guards both matter.

Progression triggers approved guidance. Conversation uses llm_orchestrator.gd,
supplying scenario facts, next step, approved guidance and at most six completed
dialogue turns. Anna's 'what happened' fact is scripted. Other dialogue can be
generated with fixed fallbacks. Dialogue animation labels do not advance CPR.

Audio checks exact-text clips/cache before configured TTS. No matching recording
plus failed TTS can leave text and audio_clip_missing, not spoken output.
Old/cancelled instructions may be discarded. Automatic listening resumes when
preparation/playback finishes. It is not a continuously overlapping conversation.

## 7. Timing defaults

| Setting | Default | Interpretation |
|---|---|---|
| Activation | RMS >0.02 | Sound level, not confidence |
| Pre-roll | 0.35 s | Earlier audio retained |
| Separate minimum-age gate | Removed | Redundant with longer trailing silence |
| Trailing silence | >1.2 s | Wait after last loud block |
| Recording cap | Disabled (0) | Current source; no automatic duration cut |
| Cloud ASR deadline | 0: disabled | May wait indefinitely; restart cancels |
| Local ASR deadline | 8 s/attempt | One transport retry, at most two attempts |
| Cloud LLM/TTS deadline | 2 s | Config clamps 0.1–2 s |
| Local LLM deadline | 45 s | Loopback request |
| Local TTS deadline | 8 s | Loopback request |
| CCBM deadline | Native process 8 s; desktop HTTP 10 s | Limits, not intentional waits |
| Confirmation lifetime | 30 s | Validity, not deliberate delay |
| Confirmation clip duration | About 2.5–4.6 s | Depends on language/question |
| Dialogue request spacing | Minimum 0.5 s | First call need not wait |
| Stale queued guidance | 30 s | Old item may be discarded |
| Fuzzy benchmark on PC | About 0.027 ms/check | Not Quest or full response latency |

From the end of speech, total delay is silence wait + ASR + interpretation +
CCBM + reply preparation/queue. Timeouts are deadlines, not delays paid on every
successful request. Fuzzy confirmation adds a question, your answer, another
silence wait and ASR request.

Illustrative, not measured: speech at 0–2 s; recording ends near 3.2 s. If ASR
takes 1 s, text arrives near 4.2 s. Exact matching skips the LLM. If CCBM then
takes 0.1 s and the next audio is ready/unqueued, voice could start near 4.3 s:
about 2.3 s after speech ended. Different servers/queues change that result.

Latest completed local validation: 49 suites, zero failures/no script errors.
This does not measure headset recognition accuracy or verify deployed models.

## Appendix: current lists

The following are copied from source. Vocabulary hints, exact interpretation
phrases and two-breath reports are distinct lists, not interchangeable layers.


### Vocabulary prompts

**en** (34 entries)

CPR, resuscitation, scene safety, surroundings, safe, unsafe, response, responding, unresponsive, consciousness, breathing, normal breathing, abnormal breathing, gasping, airway, head tilt, chin lift, emergency services, ambulance, 112, one one two, Anna, Jan, chest compressions, sternum, compression depth, compression rate, recoil, rescue breath, rescue breaths, first breath, second breath, two breaths, handover

**de** (39 entries)

Reanimation, Wiederbelebung, Umgebung, Sicherheit, sicher, unsicher, Bewusstsein, Reaktion, reagiert, nicht, ansprechbar, bewusstlos, Atmung, atmet, normal, nicht normal, Schnappatmung, Atemwege, Kopf überstrecken, Kinn anheben, Notruf, Rettungsdienst, Krankenwagen, 112, eins eins zwei, Anna, Jan, Herzdruckmassage, Brustkorb, Brustbein, Kompressionstiefe, Kompressionsfrequenz, Entlastung, Beatmung, Atemspende, erste Beatmung, zweite Beatmung, zwei Beatmungen, Übergabe

**pl** (33 entries)

resuscytacja, bezpieczeństwo, otoczenie, bezpieczne, niebezpieczne, przytomność, reakcja, reaguje, nie, nieprzytomny, oddychanie, oddycha, prawidłowo, nieprawidłowo, oddech agonalny, drogi oddechowe, odchylenie głowy, uniesienie bródki, pogotowie, karetka, 112, sto dwanaście, Anna, Jan, uciski klatki piersiowej, mostek, głębokość ucisków, tempo ucisków, oddech ratowniczy, pierwszy oddech, drugi oddech, dwa oddechy, przekazanie pacjenta

### Primary phrases

**start**

- start exercise
- start the exercise
- übung starten
- rozpocznij ćwiczenie

**begin_check**

- the scene is safe
- scene is safe
- die umgebung ist sicher
- miejsce jest bezpieczne

**check_responsiveness**

- he is not responding
- the patient is not responding
- er reagiert nicht
- pacjent nie reaguje

**call_emergency**

- anna please call 112
- please call 112
- anna call 112
- bitte ruf 112 an
- anna ruf 112 an
- zadzwoń pod 112

**check_breathing**

- he is not breathing normally
- the patient is not breathing normally
- er atmet nicht normal
- pacjent nie oddycha prawidłowo

**ventilation**

- i have given one rescue breath
- ich habe eine beatmung gegeben
- wykonałem jeden oddech ratowniczy
- wykonałam jeden oddech ratowniczy

**compression_only**

- use compression only mode
- nur herzdruckmassage
- tylko uciski klatki piersiowej

**handover**

- hand over the patient
- patienten übergeben
- przekaż pacjenta

### Additional phrases

**begin_check**

- it is safe to approach
- the surroundings are safe
- i checked the surroundings and the scene is safe
- die umgebung ist abgesichert
- ich kann mich sicher nähern
- ich habe die umgebung geprüft sie ist sicher
- można bezpiecznie podejść
- miejsce zdarzenia jest bezpieczne
- sprawdziłem otoczenie jest bezpieczne
- sprawdziłam otoczenie jest bezpieczne

**check_responsiveness**

- he did not respond
- he did not react
- there is no response
- he does not respond to my voice
- der patient reagiert nicht auf ansprechen
- er reagiert nicht auf meine ansprache
- ich habe ihn angesprochen er reagiert nicht
- pacjent nie reaguje na mój głos
- pacjent nie reaguje na wołanie
- nie ma reakcji

**call_emergency**

- anna please phone 112
- anna please call an ambulance
- please call emergency services
- anna ruf bitte die 112 an
- anna ruf bitte den rettungsdienst an
- bitte wählen sie die 112
- anno zadzwoń proszę pod 112
- anno wezwij pogotowie
- proszę wezwać pogotowie

**check_breathing**

- he is not breathing at all
- there is no normal breathing
- i checked his breathing it is not normal
- er atmet überhaupt nicht
- ich habe die atmung geprüft er atmet nicht normal
- es ist keine normale atmung vorhanden
- pacjent wcale nie oddycha
- nie ma prawidłowego oddechu
- sprawdziłem oddech pacjent nie oddycha prawidłowo
- sprawdziłam oddech pacjent nie oddycha prawidłowo

**ventilation**

- one rescue breath completed
- the first rescue breath is complete
- the second rescue breath is complete
- i have delivered one rescue breath
- ich habe die erste beatmung durchgeführt
- ich habe die zweite beatmung durchgeführt
- die erste beatmung ist durchgeführt
- die zweite beatmung ist durchgeführt
- pierwszy oddech ratowniczy wykonany
- drugi oddech ratowniczy wykonany
- pierwszy oddech wykonany
- drugi oddech wykonany

**compression_only**

- select compression only mode
- choose compression only mode
- modus nur herzdruckmassage wählen
- nur herzdruckmassage auswählen
- wybieram tryb samych ucisków
- wybieram same uciski klatki piersiowej

**handover**

- please hand over the patient
- hand the patient over to the ambulance crew
- bitte den patienten übergeben
- patienten an den rettungsdienst übergeben
- przekaż pacjenta ratownikom
- proszę przekazać pacjenta ratownikom

### Original alternatives

**check_responsiveness**

- he isn't responding
- the patient isn't responding
- no response
- he is unresponsive
- the patient is unresponsive

**check_breathing**

- he isn't breathing normally
- he is not breathing
- he isn't breathing
- the patient is not breathing
- no normal breathing

**begin_check**

- the area is safe
- the scene is clear

**call_emergency**

- anna please call one one two
- please call one one two
- anna call emergency services
- anna please call emergency services

**ventilation**

- i gave one rescue breath
- i have given a rescue breath
- i have given the first rescue breath
- i have given the second rescue breath
- i gave the first rescue breath
- i gave the second rescue breath
- i have given the first breath
- i have given the second breath
- i've given the first breath
- i've given the second breath
- i gave the first breath
- i gave the second breath
- we have given the first breath
- we have given the second breath

### Explicit two-breath reports

- two rescue breaths are given
- two rescue breaths have been given
- both rescue breaths are given
- both rescue breaths have been given
- i have given two rescue breaths
- i gave two rescue breaths
- i have given two breaths
- i gave two breaths
- i have given him two breaths
- i have given both breaths
- i have completed both rescue breaths
- i have given 2 rescue breaths
- i have given 2 breaths
- ich habe zwei beatmungen gegeben
- ich habe beide beatmungen durchgeführt
- ich habe beide beatmungen gegeben
- ich habe zwei beatmungen durchgeführt
- ich habe zwei beatmungen gemacht
- ich habe beide beatmungen gemacht
- wir haben zwei beatmungen gegeben
- wir haben beide beatmungen gegeben
- zwei beatmungen gegeben
- zwei beatmungen sind gegeben
- beide beatmungen sind gegeben
- zwei beatmungen durchgeführt
- beide beatmungen durchgeführt
- ich habe zwei atemspenden gegeben
- ich habe beide atemspenden gegeben
- zwei atemspenden gegeben
- beide atemspenden gegeben
- ich habe zweimal beatmet
- ich habe zwei mal beatmet
- ich habe ihn zweimal beatmet
- ich habe ihn zwei mal beatmet
- ich habe 2 beatmungen gegeben
- ich habe 2 atemspenden gegeben
- ich habe 2 mal beatmet
- wykonałem dwa oddechy ratownicze
- wykonałam dwa oddechy ratownicze
- wykonałem dwa oddechy
- wykonałam dwa oddechy
- wykonałem oba oddechy
- wykonałam oba oddechy
- wykonałem oba oddechy ratownicze
- wykonałam oba oddechy ratownicze
- zrobiłem dwa oddechy
- zrobiłam dwa oddechy
- zrobiłem dwa oddechy ratownicze
- zrobiłam dwa oddechy ratownicze
- dałem dwa oddechy
- dałam dwa oddechy
- dałem dwa oddechy ratownicze
- dałam dwa oddechy ratownicze
- dwa oddechy wykonane
- dwa oddechy ratownicze wykonane
- oba oddechy wykonane
- oba oddechy ratownicze wykonane
- wykonałem 2 oddechy
- wykonałam 2 oddechy
- wykonałem 2 oddechy ratownicze
- wykonałam 2 oddechy ratownicze
