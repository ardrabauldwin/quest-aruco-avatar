# English script: one witness, no AED

**Development update, 2026-10-05:** the source now routes explicit spoken reports
through CCBM instead of routine progression buttons. Native-engine and desktop
HTTP tests passed; microphone/Quest tests and a new APK are still pending.
The previously delivered English APK still has the earlier button workflow.
See [CCBM setup and supported phrases](../integrations/ccbm/README.md).

**Natural wording:** recognised text that does not match a fixed phrase now goes
to a separate meaning-extraction request using the configured language model.
It distinguishes completed reports, requests, questions, intentions, uncertainty,
and ordinary conversation. Only validated report/request structures reach CCBM;
the existing scenario guards still apply. For example, a reported lack of response
may advance assessment; planning to check, asking about responsiveness, or
reporting that the patient DOES respond must not trigger that transition.
Ambiguity, malformed output or service failure produces a localised request to
restate the completed check and finding. No automatic acceptance of a bare "yes"
is implemented. Clarification is displayed; speech requires working TTS.
This is not physical verification. Structured-output tests do not establish the
live language model's recognition accuracy; real EN/DE/PL microphone trials remain.

Direct translations of the active German scripted lines. The user is the real rescuer; Anna is the only virtual witness. Conditional replies are not all spoken in every session. Live cloud replies can vary.

| Speaker / occasion | German source | English translation |
|---|---|---|
| Instructor | Wir beginnen die Übung. Prüfen Sie zuerst, ob die Person reagiert. | We are starting the exercise. First check whether the person responds. |
| Anna | Hilfe! Mein Mann ist einfach umgefallen! Bitte helfen Sie ihm! | Help! My husband has just collapsed! Please help him! |
| Anna, if the learner waits | Bitte, tun Sie doch etwas! | Please, do something! |
| Instructor | Sprechen Sie die Person laut an und rütteln Sie sie vorsichtig an den Schultern. | Speak loudly to the person and gently shake their shoulders. |
| Anna, after the responsiveness action | Jan! Jan, hörst du mich? | Jan! Jan, can you hear me? |
| Instructor | Keine Reaktion? Rufen Sie sofort hundertzwölf an, mit Lautsprecher. Dann Atemwege öffnen und die Atmung höchstens zehn Sekunden prüfen. | No response? Call one one two immediately, on speakerphone. Then open the airway and check breathing for no more than ten seconds. |
| Anna, emergency-call reply | Ich rufe den Rettungsdienst unter hundertzwölf an. | I am calling the emergency services on one one two. |
| Instructor | Beginnen Sie die Herzdruckmassage: dreißig Kompressionen und zwei Beatmungen. | Begin chest compressions: thirty compressions and two rescue breaths. |
| Anna, reassurance reply | Ich bleibe ruhig. Bitte sagen Sie mir, wie ich helfen kann. | I will stay calm. Please tell me how I can help. |
| Anna, thanks reply | Danke, dass Sie helfen. Ich bleibe hier. | Thank you for helping. I will stay here. |
| Instructor | Die Übung ist beendet. Besprechen Sie jetzt Ihr Vorgehen. | The exercise has ended. Now discuss what you did. |

Choose **EN + Own language** for English instructions and English Anna. **EN + Neighbour language** gives English instructions and German Anna. DE/PL neighbour pairing remains unchanged.

The emergency number remains **112**, as in the German source and this Germany/Poland scenario. English does not change the scenario location.

English scripted recordings use Windows System.Speech, Microsoft Zira Desktop. These are new synthetic recordings, not voice-matched versions of the existing German/Polish actors. Live microphone recognition and free conversation still need the configured cloud services.

Validation: 14 suites passed; DE/PL/EN scenario smoke passed. No headset installation or live English microphone test is claimed.
