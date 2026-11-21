# Continuous AED training pattern

The main exercise repeats **shock advised → shock advised → no shock advised**, indefinitely until an explicit ending such as handover/reset. These are scripted teaching decisions, not ECG measurements or predictions of recovery. The random 50% recovery and forced third-shock recovery rules were removed.

Each completed shock or no-shock CPR return advances the pattern once. Interrupted/repeated analysis does not skip entries. After every outcome the current compression set resets to zero, the next accepted press is one, and the session total is preserved. The next reassessment is due after the existing 120 seconds in the simulated CPR state. Two clearance checks remain required for a shock, and tracked contact cancels clearance. A no-shock result never implies recovery.

Start/reset returns to the first pattern entry. Earlier safety, responsiveness, 112, airway/breathing and CPR steps are unchanged. The explicit trainer-only recovery/handover controls remain; there is no automatic recovery or shock-count limit. The instructor explains the scripted pattern in English, German and Polish. CCBM receives each actual decision through the existing native observation protocol; no native model rebuild is needed for this pattern selection.

Source update only: no APK build, installation, commit or push.
