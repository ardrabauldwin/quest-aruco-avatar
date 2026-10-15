# Natural conversation and CPR guidance

Anna is the worried witness; the instructor provides CPR guidance. Their voices
are different in English, German and Polish. The selected exercise keeps one
witness and no AED interaction. AED guidance remains available as an explanation;
this is not a complete AED training course.

## Exercise sequence and example speech

Choose your language, complete patient placement and saved controller adjustment,
then press Start training and enable the microphone. Wait for the current voice
to finish before speaking; playback still pauses microphone capture to prevent
the app recognising its own voice. USB must remain connected for these PC services.

| Step | What to do in the simulation | Example report or question |
|---|---|---|
| Safety | Check the surroundings | “The scene is safe.” |
| Responsiveness | Speak to the patient and gently tap the shoulders | “Can you hear me? I checked him. He is not responding.” |
| Emergency call | Ask Anna to call 112 on speaker | “Anna, please call 112 and put the phone on speaker.” |
| Airway and breathing | Head tilt/chin lift; assess normal breathing for no more than ten seconds | “I checked his breathing. He is not breathing normally.” |
| Compressions | Perform thirty compressions; existing counter supplies events | “Instructor, how deep should I press?” |
| First breath | Perform one rescue breath if trained and able | “I have given one rescue breath.” |
| Second breath | Perform the second breath | “I have given one rescue breath.” |
| Repeat | Resume compressions and repeat the cycle | “What should I do next?” |
| Compression-only alternative | Select when unable to give breaths | “I cannot give breaths. Use compression-only CPR.” |
| Handover | Continue until the trainer confirms help has arrived, then request handover | “I am handing over the patient.” |
| Debrief | Review counts, timing, pauses and communication | Read the existing results panel. |

These are examples, not an exact script to recite. Ambiguous wording may still
need clarification. Speech reports do not prove correct physical technique;
hand-tracked depth remains an estimate.

Ask “What should I do next?”, “How do I check breathing?” or name the instructor
to request guidance. Address Anna by name to ask witness questions: “Anna, what
is his name?” Known patient facts are limited; she must not invent medical history.
Only accepted observations and existing scenario guards advance the exercise.
Questions and generated replies never submit clinical actions.

## Code and runtime

- `scripts/ai/training_coach.gd` maps the existing scenario state and cycle counts
  to the next task. `data/coach_steps.json` contains all approved guidance in EN/DE/PL.
- `scripts/main.gd` announces changed tasks, offers one assessment reminder after
  thirty seconds, routes help questions and ignores stale instructor replies.
- `scripts/ai/llm_orchestrator.gd` retains six recent conversation turns and gives
  the local model the current task, known facts and approved guidance. Resets and
  language changes clear that conversation memory.
- `scripts/api/uni_api_client.gd` uses `api.local_ai_url` when configured; cloud
  configuration remains available for other installations.
- `tools/local_dialogue_server.py` runs Qwen3 4B Instruct through Ollama on the PC
  GPU and Piper TTS on the PC. It listens only on loopback port 8768 and logs no
  request bodies. Voices and model-card attribution remain in `/opt/naret-dialogue/voices`.
- Local Whisper large-v3 runs separately on port 8767. CCBM remains on port 8766.
  None of these models run inside the Quest APK.

Start the local speech service and CCBM as before, plus
`bash tools/start_local_dialogue.sh` in Ubuntu. Run
`python tools/connect_local_dialogue.py` in Windows to configure the attached
Quest and enable USB forwarding. It preserves calibration and credentials.
After reconnecting USB, re-enable forwarding for ports 8766, 8767 and 8768.

Guidance follows the [2025 adult BLS guidance](https://www.resus.org.uk/professional-library/2025-resuscitation-guidelines/adult-basic-life-support-guidelines).
The local model can still produce imperfect wording. Clinical progression is
kept outside its generated response, and stage announcements use approved text.
