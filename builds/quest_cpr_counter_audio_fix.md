SUPERSEDED: Use quest_cpr_keep_count.apk. The user does not want slow presses to reset the count.

# Counter and audio update - 2026-09-08

APK: quest_cpr_counter_audio_fix.apk
SHA-256: 7205C4964C3E70427B482D9DA43999FCCA2CE3D2E1F5EDAFBCF62D52458BBD6B

Source: local changes to 4dae803 in cpr_motion_session.gd, cpr_metronome.gd, cpr_hand_zone.gd and cpr_feedback_hud.gd; regression tests updated alongside them.

- Complete 5 cm estimated hand excursions with return count independently of beep phase.
- A tracked interval/stroke longer than 0.70 s resets the current set to 0 and shows Too slow. Completed lifetime total is retained. Tracking loss preserves counts and discards incomplete motion.
- Beeps use a 90 ms tone at -3 dB on Master (previously 55 ms at -14 dB).
- HUD shows tracking status, reset feedback and estimated hand travel.

Validation: motion-session regression suite PASS; synthetic XR hand joint/HUD/audio playback suite PASS. Android debug export completed, expected scripts and ARM64 OpenCV library present, APK v2 signature verified. Desktop tests report the existing missing Windows OpenCV extension; synthetic tests do not require it. Export reports the existing desktop-only CameraServerExtension ARM64 warning.

No Quest was connected. Installation, real hand tracking, and headset audibility remain unverified.

