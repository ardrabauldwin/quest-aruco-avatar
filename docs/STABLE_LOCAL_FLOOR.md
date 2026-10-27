# One stable floor-height source

Patient and character floor height uses only the OpenXR floor-based tracking
reference provided by `NaretOpenXRSetup.floor_height_world()`. It no longer
switches to a room-scan floor. Room scanning continues to supply room geometry.

At setup, local-floor readings collected over at least 1 second must agree
within a total 1 cm height range before their arithmetic mean is accepted.
The comparison is made in tracking-reference coordinates, so a recenter does
not look like floor noise. A larger spread or missing reading restarts the
window. There is no minimum sample count or maximum time-gap threshold.
Consequently, this is an elapsed collection window; it cannot prove the floor
was tracked during a pause with no callbacks. Multiple callbacks with the same
timestamp are counted once. The duration and spread are prototype thresholds,
not headset-validated values.
There is no timeout that forces acceptance of unstable data.

After locking, later floor readings do not replace the accepted height. It is
stored relative to `XROrigin * XRServer.reference_frame`, so changing
those coordinate transforms moves the same accepted plane into world space.
This handles coordinate recentering; it cannot detect an inaccurate physical
floor setup or a runtime boundary reset that changes no observable transform.
After changing the system's physical floor setup, relaunch the app.

Existing optional fingertip calibration, chest measurement and patient height
nudges remain available. A saved fingertip offset tagged `local_floor` applies;
one tagged `room_scan` is retained in the file but is not applied to a different
source. To replace an old room-scan correction, explicitly recalibrate floor.
Saved patient/model alignment is not rewritten by this change.

No valid local-floor sample at startup means no new floor lock; no zero-height
or room-scan fallback is invented. Tests cover averaging, unstable input, sparse samples,
duplicate timestamps, missing input, jitter, jumps,
tracking-reference changes and scene-origin changes. Headset testing remains
necessary for the runtime's recenter behaviour.
