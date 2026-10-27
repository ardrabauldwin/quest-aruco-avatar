# One floor-height reference

Patient and character floor height uses only the OpenXR floor-based tracking
reference provided by `NaretOpenXRSetup.floor_height_world()`. It does not
switch to a room-scan floor. Room scanning continues to supply room geometry.

The provider returns an established tracking-floor coordinate, not an
independent physical floor measurement per frame. Therefore there is no
averaging period, agreement threshold, sample-count requirement, gap limit or
restart loop. Wait for a valid reference, then retain it for the app session.
This avoids presenting repeated reads of the same coordinate as sensor samples.

The reference is stored relative to `XROrigin * XRServer.reference_frame`.
Coordinate recentering or a changed scene origin transforms that same accepted
plane into world space. This does not detect an inaccurate physical floor setup
or a runtime boundary reset that changes no observable transform. After changing
the system's physical floor setup, relaunch the app.

Existing optional fingertip calibration, chest measurement and patient height
nudges remain available. Fingertip recalibration explicitly changes the offset
applied to the retained floor reference. A saved offset tagged `local_floor`
applies; one tagged `room_scan` is kept in the file but not applied to a different
source. To replace an old room-scan correction, explicitly recalibrate floor.
Saved patient/model alignment is not rewritten by this change.

No valid local-floor reference at startup means no new floor lock; no zero-height
or room-scan fallback is invented. Tests cover missing input, immediate use of a
valid reference, retention, explicit fingertip correction, and coordinate changes.
These checks do not establish physical floor accuracy on Quest. Headset testing
is still required.
