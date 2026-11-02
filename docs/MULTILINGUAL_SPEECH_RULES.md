# Multilingual speech changes

Vocabulary hints are sent in the multipart `prompt` field for English, German
and Polish. The words describe the exercise vocabulary, not the expected next
answer. They do not change Whisper weights or replace the recording. Both the
cloud and loopback transports receive the field; actual AppHub prompt support
and recognition benefit require a live endpoint check. whisper.cpp's server
supports `prompt`. The GPU upload handler forwards it to faster-whisper's
`initial_prompt`, bounded to 512 characters. The existing optional hotwords
switch remains separate. Restart a deployed GPU server to pick up that change.

The expanded lists cover scene safety, response/consciousness, breathing and
gasping, airway manoeuvres, calling emergency services, compressions and
ventilation, and handover. They include common alternatives (Beatmung /
Atemspende; pogotowie / karetka), names already used in the scenario (Anna,
Jan), and spoken forms of 112. Opposite findings remain represented: safe /
unsafe, sicher / unsicher, prawidłowo / nieprawidłowo. Vocabulary is not used
to map unconsciousness to unresponsiveness or infer any clinical finding.
Each language stays within the GPU handler's 512-character bound. These are
draft language choices and still need native-speaker and recorded-audio review;
a larger hint list has not been shown to outperform the earlier short list.

`concept_reports.gd` adds a deterministic whole-report slot grammar to the
existing exact-phrase fast path. It covers completed safety, responsiveness,
breathing and single-breath reports in all three languages. It permits specified
fillers, subjects and verb forms rather than arbitrary substrings or arbitrary
word order. Unknown clauses, questions, future plans, quoted reports and
conflicting statements fall through. A rejection here does not block the
existing language-model fallback; its own validation still applies.

Two-breath reports continue through the existing separate pair-report handler.
Mishearing confirmation now runs in the trainee's selected language, independent
of the bystander's language in neighbour mode. It accepts localized yes/no only
for an unexpired pending proposal in the same stage and language. A proposal is
consumed once. Breath pairs retain their count and use a distinct question.
German/Polish also accept selected natural short reports ("Keine Reaktion",
"Brak reakcji"), alternate completed breath forms, and explicit requests to
Anna to call 112. Selected "Ich glaube..." / "Myślę, że..." reports ask for
confirmation rather than count as completed findings. Natural affirmative and
negative replies work only while a matching proposal is pending. These are
language-rule additions, not demonstrated ASR accuracy gains.

`fuzzy_speech.gd` compares a short report with same-language anchors using
Godot's string similarity. Prototype minimum score is 0.80, with a 0.08 margin
over the next report class. These values are not learned or accuracy estimates.
All report classes are considered before checking allowed actions, so the
current stage cannot boost an unrelated sentence. Candidates must have the
same word count with just one different word and identical negation/count
tokens. Questions, known opposite findings and compound/future markers are
excluded. Legacy observed English aliases remain for compatibility, including
"scene a save", which is outside this conservative one-word-change grammar.
Every fuzzy match requires confirmation, including high scores; similarity
alone must not silently reverse a negation or count an uncertain breath.

Eighteen exact-text Piper clips provide questions and retry messages offline.
They are loaded by text/language into the instructor cache. One- and two-breath
questions never share a mismatching fallback recording. Regenerate with
`tools/generate_confirmation_clips.py` in the existing Piper environment;
voice model cards accompany the clips. No new model training, automatic
acceptance of fuzzy reports or implicit inference from scenario order was added.
The CCBM and scenario guards still decide whether a recognised report can
advance the current stage; speech does not verify physical performance.

Validation: run `tests/run_tests.gd` and `python tools/test_gpu_asr_prompt.py`.
These are software checks, not measured German/Polish recognition accuracy.
Compare real headset audio with and without hints before claiming improvement;
include normal/abnormal findings, intentions, questions, noise and silence.

Implementation references:
- https://github.com/ggml-org/whisper.cpp/blob/master/examples/server/server.cpp
- https://github.com/SYSTRAN/faster-whisper/blob/master/faster_whisper/transcribe.py
