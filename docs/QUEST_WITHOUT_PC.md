# Quest runtime without a development PC

Requirement: the installed Quest app must not require a laptop, WSL, adb reverse,
or USB forwarding during training. Internet-connected backend services are
allowed. This is different from a fully offline, on-headset AI implementation.

The Android API client now ignores legacy PC ASR and AI/TTS loopback overrides.
Desktop development routes remain available. Full AppHub provisioning clears
both local_asr_url and local_ai_url; speech-only provisioning intentionally
retains other settings for its existing limited purpose. Do not use speech-only
provisioning to claim the complete app was made PC independent.

Current service mapping:

| Component | Quest runtime path | Remaining requirement |
|---|---|---|
| Recording, hand/marker tracking, UI | On Quest | Device permissions/assets |
| Exact/grammar/fuzzy report matching | On Quest | Included source/assets |
| Confirmation and baked guidance clips | On Quest | Included audio assets |
| ASR | Direct HTTPS AppHub request | Network and valid per-device API configuration |
| Free-text interpretation/dialogue | Direct HTTPS configured LLM | Valid model available on that service |
| Generated voice | Direct HTTPS configured TTS | Working service/voice; cached recordings cover only known text |
| CCBM progression | Real packaged native ARM64 filter on Quest | Native AAR/export plugin and matching model table included |

CCBM is now packaged for Android as the real upstream filter compiled for ARM64.
It runs off the render thread, using a fresh, time-limited native process per
inference. No CCBM HTTP endpoint is used on Quest. Existing external-worker support
remains for desktop development. PDDL generation and native compilation happen
on the build machine; customers need neither that compiler nor a PC runtime.

Verification on the connected Quest 3: 19 native observation prefixes passed;
the isolated Godot diagnostic APK also passed 17 prefixes using its installed
native artifact and packaged state table, at approximately 27–42 ms per request.
Those tests cover inference and packaging, not microphone accuracy or all XR flows.

This does not yet establish an end-to-end tested no-PC training session.
Validate ASR, free interpretation, voices and progression with the USB
cable disconnected and all laptop services stopped before calling it complete.
No shared API credential is embedded in the APK or source.

Product licensing remains separate: the upstream CCBM distribution is marked
CC BY-NC-SA 4.0. This technical port does not grant commercial-use permission.
The exact upstream license is included with the runtime and source provenance.
