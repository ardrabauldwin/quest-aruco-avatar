# NaReT CPR Witness: merged application

This version uses Denis's patient, witness, language, interface and scenario
modules with the user's marker camera worker, three-marker transforms, startup
estimator, viewer-motion gate and hand compression detector. It is a focused
CPR and communication exercise, not the original complete AED scenario.

## What happens in the headset

1. Open **NaReT CPR Witness**. Grant camera, headset-camera and microphone access.
   OpenXR supplies the room/head/hand tracking and passthrough. The patient remains
   hidden while initial marker observations are collected.
2. Show markers **0, 1 and 2**, with **100 mm black squares**. The camera worker
   comes from the user's v61 source branch. It uses the user's native OpenCV
   library, a background detection thread, half-resolution processing, raw
   calibrated focal lengths and the inherited 50 ms head-pose timing assumption.
   There is no 0.937/0.9468 multiplier or beyond-1.2 m correction in this build.
3. Each detected marker is transformed to the common reference with the saved
   marker-to-common calibration. Only markers in the same result are fused.
   Position and sign-aligned rotation are averaged; the body heading is flattened
   as in the user's provider. This constrains orientation, not floor height.
4. Startup uses coordinate-median position and a measured rotation medoid.
   Estimates at observations 30, 33, 36, etc. must change by at most 1.5 mm and
   1 degree on four consecutive comparisons. Earliest acceptance is observation
   42. The inherited observation-100 fallback can accept without convergence.
5. Open **Calibration**, align Denis's model/reference to the real mannequin and
   save. The shipped common-to-patient bridge sets axis convention only; it is
   NOT a measured alignment of this new model. This calibration is mandatory
   before the headset Start action is accepted. Saved calibration is reused in
   later sessions; startup still relearns the world position.
6. Choose **DE or PL** and **own language or neighbour language**. In own-language
   mode Anna speaks the chosen language. In neighbour-language mode she speaks
   the other language while instructions remain in the chosen language.
7. Start. There is one virtual witness, **Anna**, one virtual patient and you,
   the real rescuer. Confirm the scenario's initial checks and simulated emergency
   call through its actions. The witness never takes over or generates presses.
8. Speak aloud. Voice activity starts microphone capture; after the speech ends,
   the configured service transcribes it, the dialogue service creates Anna's
   reply, and speech output/subtitles present it. API credentials are configured
   on the device, never bundled in the APK. Without the service there is no live
   speech recognition; scripted audio and buttons still work. Cloud dialogue
   cannot confirm physical actions or change patient vital state.
9. During the CPR state the user's hand detector feeds compression events
   directly to the scenario. The mannequin simulator is not in this input path.
   Count/rate and hand placement feedback are available. Hand excursion is an
   estimate, not verified physical compression depth. Breaths are explicitly
   simulated via the interface; they are not automatically measured.
10. Finish via handover to reach the debrief. The app exports session actions,
    counts, timings and errors. Ending does not assert that the patient recovered.
    There are no AED model, AED actions or required AED transitions in this mode.

## Placement after startup

The migrated gate holds while head speed exceeds 0.15 m/s or yaw rate exceeds
20 degrees/s (0.3 s window). After 0.5 s stillness it judges five readings.
An initial horizontal/yaw difference within 10 cm AND 10 degrees is remembered
and subtracted. Subsequent residual changes can still move the patient through
the stabilizer. Over 30 cm OR 25 degrees with three full-evidence results retains
the old override. Ordinary updates beyond 1.8 m hold. These inherited rules can
misclassify physical moves or persistent measurement errors; this port does not
prove they solve side drift. Once placed, the vertical anchor coordinate holds.

## What still requires physical verification

- The saved sticker layout still matches the actual sticker positions.
- Calibration of Denis's patient and hand target against the real mannequin.
- Headset camera selection, metric distances, timing and front/side alignment.
- Actual hand counts, occlusion/recovery and sustained headset performance.
- Quest microphone, permissions, configured cloud service and language quality.

Desktop tests and an APK export cannot establish these physical results.
