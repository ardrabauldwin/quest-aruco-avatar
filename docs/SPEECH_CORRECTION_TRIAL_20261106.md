# CPR vocabulary and LLM correction trial — 6 November 2026

## Outcome

The active fuzzy path is retained. After this trial, the user requested keeping the LLM: the correction generator is now connected in source as a fallback after unresolved LLM interpretation. Clear reports, questions and intentions do not enter correction; failed service requests do not trigger another request. A validated proposal requires explicit confirmation. The former expected-step confirmation fallback was removed. New utterances cancel stale responses; changed scenario context or language rejects a delayed proposal. The exact/concept/fuzzy and ordinary interpreter paths remain active. No APK was built, installed, committed or pushed.

The multilingual vocabulary hints were revised in source; their ASR accuracy has not been measured with a WAV A/B experiment. Do not equate a larger vocabulary with proven better recognition.

## Implementation

- `scripts/ai/asr_correction_proposal.gd`: protocol for keep/propose/repeat; no expected step supplied. Parses model suggestions conservatively and returns `proposal`, never a directly executable observation.
- Semantic guards preserve negation, explicit count words/digits and intention markers. Corrected wording must independently map to a supported report/request. Unknown/foreign-script/malformed outputs are rejected. These guards do not prove the original intention; explicit human confirmation remains necessary.
- `scripts/scenario/speech_confirmation.gd`: existing pending-confirmation method can now carry an explicit one/two breath count. Confirmation remains limited by language, current scenario context, action availability, one-time consumption and expiry.
- `data/cpr_speech_vocabulary.json`: English/German/Polish vocabulary grouped by safety, responsiveness, breathing, airway, emergency call, compressions, ventilation, handover and patient history. Includes positive and negative findings, and count variants; no expected clinical answer is provided.
- `scripts/api/uni_api_client.gd`: revised compact vocabulary hints retain the existing transport limit. No ASR weights or dialogue weights were changed.

| Language | Curated entries in trial lexicon | Comma-separated ASR hint items | ASR hint characters |
|---|---:|---:|---:|
| en | 61 | 42 | 442 |
| de | 61 | 41 | 467 |
| pl | 60 | 39 | 448 |

The short hints are spelling/decoding cues, not completed report templates. The broader lexicon is supplied to the correction fallback. Polish wording needs native-speaker review before course use.

## Live model test

Model: `unsloth/gemma-4-31B-it-qat-GGUF:UD-Q4_K_XL`. Used the configured service with the same 0.3 sampling temperature and 160-token reply budget as the app. Credential stayed in memory and was not copied into reports.

37 cases, repeated twice: 14 requested local repairs, 7 clear/positive statements and 16 controls. Two English cases represent user-reported rescue-bread mishearing patterns; the rest are constructed challenge cases. These are text-only tests, not 37 recorded audio sessions.

| Measure | Result |
|---|---:|
| Live responses | 74 |
| Requested repairs yielding valid correct proposals | 26/28 |
| Clear statements kept unchanged | 14/14 |
| Control trials yielding no allowed proposal | 32/32 |
| Raw model proposals on control trials | 8 |
| Such proposals passing validator | 0 |
| Median request time | 1.554 s |

The model proposed spelling repairs inside plans, denials, questions and an unnumbered breath statement. All were blocked by the report validator. This demonstrates why prompts alone are insufficient; it is not evidence that all possible dangerous suggestions are blocked.

The two requested-repair trials without proposals were the same Polish sentence: `Pacjent nie oddycha prawidlowo.` The model kept it unchanged rather than adding the diacritic. Meaning preservation is reasonable, but it did not supply the requested correction. This is not a false medical finding.

The current fuzzy-confirmation stage offered matching proposals for 13/14 repair cases, while the new validated stage did so for 13/14 in each round. They missed different cases. This is a comparison of proposal coverage, not full end-to-end application accuracy, WER, or proof of superiority. The normal existing interpreter might handle cases without a fuzzy proposal.

The first exploratory run had a UTF-8 decoding problem in the Python harness. It was corrected and the full 74-response run repeated; only the corrected run above is used for conclusions.

## Verification

69 suites, zero failures; smoke test passed. Tests cover missing/changed negation and counts, plans and questions, malformed JSON, script mismatch, explicit confirmation, rejecting no, changed state, unavailable actions, expiry and consuming a confirmation only once.

## Research and terminology references

- [ASR Error Correction using Large Language Models](https://arxiv.org/abs/2409.09554): unconstrained correction can be problematic; ASR hypotheses can constrain candidate generation. Our endpoint supplies one transcript, not an acoustic N-best lattice.
- [Fewer Hallucinations, More Verification](https://arxiv.org/abs/2505.24347): proposes detecting, correcting and verifying rather than trusting one unconstrained rewrite. This trial uses a simpler deterministic guard plus human confirmation; it does not reproduce their method or claim their gains.
- [Multilingual correction benchmark](https://aclanthology.org/2025.emnlp-main.320/): supports evaluating across languages instead of assuming English results transfer.
- [ERC adult BLS 2025](https://www.erc.edu/media/wrhj5sye/gl2025-04-bls-e.pdf), [German Resuscitation Council](https://www.grc-org.de/wissenschaft/leitlinien), [Polish Resuscitation Council](https://www.prc.krakow.pl/wytyczne-2025/): terminology references. We did not change the clinical training protocol.

## Next evidence needed

Test held-out, naturally spoken headset recordings with verified intended wording in all three languages; measure wrong accepted findings, useful/redundant confirmation questions, end-to-end delay and ASR word errors. Compare the original versus revised vocabulary on the same WAVs. Only then decide whether to replace the fast fuzzy path. No generic similarity threshold or confidence percentage was introduced in this trial.
