# Single-interpreter comparison — 6 November 2026

No production route changed; no APK built or installed. This is prompt conditioning, not fine-tuning.

32 text cases: 30 new constructed challenges (10 per language) and 2 observed garbled transcripts with unverified intended wording, conservatively labelled for abstention. Twelve separate prompt examples were fixed before running. The two observed cases are not verified ASR ground truth. One run per case; exploratory only.

Compared current hybrid semantic routes plus live interpreter/correction fallback against one LLM request without examples and with examples. Model: `unsloth/gemma-4-31B-it-qat-GGUF:UD-Q4_K_XL`. Same sampling temperature 0.3 and 160-token budget. No expected step supplied. All actions treated as available to isolate interpretation; not an end-to-end scenario/order test.

| Arm | Expected handling | Wrong direct actions | Median summed model time | Requests |
|---|---:|---:|---:|---:|
| current_hybrid | 27/32 | 3 | 3131.5 ms | 24 |
| single_zero_shot | 24/32 | 3 | 1132.5 ms | 32 |
| single_examples | 27/32 | 2 | 1588.0 ms | 32 |

A proposal is not an accepted action. Questions are expected to route for an answer; generated reply correctness/audio was not evaluated. Normal breathing/responsiveness are expected to preserve the opposite finding without advancing. Missing useful answers can still score as non-advancement: inspect individual results. Model-time excludes ASR, TTS, user confirmation and Godot processing. Fast paths have zero model-request time.

The consolidated prototype reuses the real app response parsers and correction guards. Explicit two-breath reports additionally require the existing whole-report pair parser. This remains a rule dependency, not a completed removal of phrase/grammar lists. Current main routing is simulated through the same helpers, not a full headset replay. All transcript labels are developer-assigned and need review, particularly Polish.

## Cases requiring review

- single_zero_shot / en3: `Anna could you ring 112 for me?` — expected action call_emergency; got ('no_action', '', 1).
- current_hybrid / en4: `I have completed two rescue breaths.` — expected action ventilation; got ('no_action', '', 1).
- single_zero_shot / en4: `I have completed two rescue breaths.` — expected action ventilation; got ('no_action', '', 1).
- single_examples / en4: `I have completed two rescue breaths.` — expected action ventilation; got ('no_action', '', 1).
- single_zero_shot / en5: `The patient is not respondding.` — expected proposal check_responsiveness; got ('action', 'check_responsiveness', 1).
- single_examples / en5: `The patient is not respondding.` — expected proposal check_responsiveness; got ('no_action', '', 1).
- current_hybrid / en9: `The vaccine is safe.` — expected no_action ; got ('action', 'begin_check', 1).
- single_zero_shot / de3: `Anna kannst du bitte den Notruf 112 wählen?` — expected action call_emergency; got ('no_action', '', 1).
- single_zero_shot / de5: `Der Patient atmet nicht normall.` — expected proposal check_breathing; got ('action', 'check_breathing', 1).
- single_examples / de5: `Der Patient atmet nicht normall.` — expected proposal check_breathing; got ('action', 'check_breathing', 1).
- current_hybrid / de9: `Der Impfstoff ist sicher.` — expected no_action ; got ('action', 'begin_check', 1).
- single_zero_shot / pl3: `Anno proszę wezwij pomoc pod numerem 112.` — expected action call_emergency; got ('no_action', '', 1).
- current_hybrid / pl4: `Podałam dwa oddechy ratownicze.` — expected action ventilation; got ('proposal', 'ventilation', 2).
- single_zero_shot / pl4: `Podałam dwa oddechy ratownicze.` — expected action ventilation; got ('no_action', '', 1).
- single_examples / pl4: `Podałam dwa oddechy ratownicze.` — expected action ventilation; got ('no_action', '', 1).
- single_zero_shot / pl5: `Pacjent nie oddycha prawidłowoo.` — expected proposal check_breathing; got ('action', 'check_breathing', 1).
- single_examples / pl5: `Pacjent nie oddycha prawidłowoo.` — expected proposal check_breathing; got ('action', 'check_breathing', 1).
- current_hybrid / pl9: `Szczepionka jest bezpieczna.` — expected no_action ; got ('action', 'begin_check', 1).

## Next decision

Do not replace production based on this small synthetic experiment. Review wrong direct actions and changed findings first; add verified audio/transcript labels, then test on different speakers without adding those evaluation utterances to prompt examples. Fine-tuning requires a separate supported training/deployment setup. Credentials were kept in memory and are absent from results.

## Constructed cases by language

| Arm | English | German | Polish |
|---|---:|---:|---:|
| current_hybrid | 8/10 | 9/10 | 8/10 |
| single_zero_shot | 7/10 | 8/10 | 7/10 |
| single_examples | 8/10 | 9/10 | 8/10 |

`error_review.json` retains the raw model decisions for each mismatch. Review whether the model misunderstood, the existing validator refused a valid paraphrase, or the required confirmation policy differed. Do not describe every mismatch as an LLM understanding failure.

## Interpretation of the mismatches

- Current hybrid: three unrelated vaccination-safety statements (English/German/Polish) were classified as `begin_check` by the existing safety helper. In the app this helper runs when scene safety is available, so this is a real first-step false-acceptance risk, not just an out-of-order simulation artefact. Production has not been patched by this experiment.
- Single request with examples: the German and Polish deliberately misspelled reports produced the intended action immediately instead of a confirmation proposal. These are confirmation-policy violations; they are NOT opposite clinical findings. The English correction proposal omitted the mandatory `breaths` field and was rejected. A single schema should avoid requiring breath counts for unrelated actions, but the experiment did not silently relax the current validator.
- Both single-request variants correctly named the action and two-breath count for the constructed English and Polish pair reports, but the existing whole-report pair parser refused their wording. Current hybrid also missed the English pair; for the Polish pair it asked a redundant confirmation. This is partly a restrictive validator/interface problem, not simply model understanding.
- Without examples, all three call requests were labelled with result `unsafe` rather than `none`, and were correctly refused by the existing request validator. Prompt examples eliminated that particular schema error in this run.

The table's `Wrong direct actions` includes both wrong-topic clinical submissions and bypassing the required confirmation policy. Those are different failures. For this run, the current hybrid had 3 wrong-topic submissions; single-zero-shot had 3 confirmation-policy violations; single-with-examples had 2 confirmation-policy violations. No opposite breathing/responsiveness finding was accepted on this dataset. This limited result is not a general safety guarantee.

## Recommendation from this run

Keep the current deployment unchanged while designing one consistent interpretation contract. A single LLM request with examples is promising: it matched the hybrid's 27/32 expected-handling score and used median 1.588 s summed model time versus 3.132 s for the hybrid on this mixed workload. This is one exploratory text run, with different prompt lengths and sequential execution; it does not establish a general latency or accuracy advantage.

Next implementation should unify the report/proposal/question schema, remove the one-breath-only interpreter restriction, and replace narrow whole-sentence pair validation with explicit count/negation/evidence checks. Separately fix or retire the overbroad safety helper. Validate these changes against new examples and verified recordings before removing production matching paths. Explicit human confirmation must remain for proposed repairs. Model examples condition requests; no weights were trained.

## Local artefacts

Experiment folder: `C:/Users/bauld/Overlay/quest-aruco-avatar/build/llm_comparison/`. Contains fixed prompt examples, evaluation cases with provenance, raw responses, parsed results, error review, source hashes, recording-label template and collection instructions. No credentials are stored there.
