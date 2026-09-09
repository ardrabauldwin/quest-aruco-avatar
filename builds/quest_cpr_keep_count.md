# Corrected counter update - 2026-09-08

Use quest_cpr_keep_count.apk. This supersedes quest_cpr_counter_audio_fix.apk.

Slow complete presses still count. Slow motion and pauses never reset the count; pace feedback says Press faster. Only explicit reset/start and the existing transition to the next 30-count cycle clear the current set.

Includes the removal of beep-phase counting restrictions and the longer, louder metronome from the previous update.

Regression tests pass for slow presses at 50 and 20 BPM, a five-second tracked pause, resumed normal cadence, tracking gaps, 30-count cycles and metronome-independent counting.

Headset installation, real hand tracking and audibility remain unverified.
