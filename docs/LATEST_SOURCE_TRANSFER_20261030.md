# Latest combined XR source for NaReT review ? 30 October 2026

This branch transfers the latest local combined application for review against
NaReT-Nachbarsprache-wird-reanimiert/naret-xr-app main (9d880a1).
The combined checkout has separate Git history. This snapshot retains the
combined history; an organisation maintainer can import its source tree onto
a review branch based on organisation main.
Original combined base: 1fa944a; includes the subsequent local source changes.

Includes the current hand menu and language controls, speech/CCBM and natural
breath-report handling, marker tracking recovery, sternum patient pivot,
floor/chest calibration, speaker placement, and green compression guide changes.
The current export preset is version 2026102921 (gizmos).
The 30/33 post-startup checkpoint experiment is included but remains opt-in;
standard placement remains the default. The historical colour-marker pipeline
is archived in integrations/colored_marker_camera, not active in the detector.

Validation on Windows with Godot 4.7.1:
- 44 test suites passed, zero failures and no script/parse/error lines.
- Offline DE/PL/EN smoke test passed, no script/parse/error lines.
- Smoke exit reports two existing ObjectDB leak warnings.
- Source credential-pattern and sensitive-filename checks passed.
These checks do not establish Quest runtime or speech-service reliability.
No new APK was built or installed as part of this source transfer.

API credentials, headset calibration, recordings, build outputs and generated
import changes are excluded. Each tester must provision their own API token;
see config.example.json and tools/configure_quest.py. Native dependencies remain
pinned Git submodules; use tools/setup_dependencies.py as documented in README.
Environment-depth rendering remains disabled after the Quest swapchain crash.

Direct push to the organisation repository is currently unavailable: the
ardrabauldwin account has READ permission, and repository forking is disabled.
An organisation maintainer can fetch this branch and push it into naret-xr-app,
or grant the account write access. This branch does not modify organisation main.
