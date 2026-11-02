# Native CCBM on Quest

This is the actual upstream particle filter, not a state-machine approximation.
Build revision: 42672c8946e42447c370c6bf19a655c93965502b.
Generated model: the adjacent d.pddl / p.pddl and d-observations.cpp.

The APK includes addons/ccbm_native/naret_ccbm_runtime.aar, containing the ARM64
PIE executable libnaret_ccbm.so. The export plugin adds that AAR to Gradle.
Native-library extraction is enabled so Android installs executable code into
its managed native library directory, not writable application data. C++ uses
the existing model's posterior and observation likelihoods without replacement.

ccbm_native.gd resolves the artifact using AndroidRuntime and the application's
class loader. It decodes/checks the bundled state-table hash and writes only
state data and observation codes to private application storage. WorkerThreadPool
runs inference outside the render thread. Each process gets a fresh filter,
has an 8-second native alarm, and exits after consuming the observation file.
The bridge still rejects stale sessions, wrong actions, unavailable actions and
posteriors below its existing 0.90 acceptance policy. No CCBM network is used on
Android, and missing/failed native code does not bypass inference.

The parser retains BLOCKED/FINISHED/unknown posterior mass; it does not silently
renormalise only the desired actions. Reset results cannot release a newer
inference's pending lock. Compressions remain locally counted by the existing
hand detector and scenario; CCBM receives only onset plus stage-level reports.
The existing 256-observation-history limit is unchanged.

## Rebuild

On a Linux build machine with the pinned upstream checkout, its existing model
generator, and a Linux Android NDK (tested r27c):

```sh
python3 integrations/ccbm/build_android.py \
  --ndk /path/to/android-ndk-r27c \
  --upstream /path/to/CCBMpublic \
  --states /path/to/matching/p.states
```

The state table must be generated from the same PDDL model via build.sh.
Generation uses the build machine; no Haskell, Python, NDK, adb reverse or PC
worker is required by the installed app. The build emits the runtime AAR and
addons/ccbm_native/model.json with state/executable hashes and upstream provenance.
Do not reuse a state table after changing the PDDL/model layout without rebuilding
and rerunning native prefix tests. Godot export needs the native export plugin
enabled and gradle_build/compress_native_libraries=true.

## Verification performed

- Native ARM64 filter executed on Quest 3: 19 valid prefixes, including repeated
  ventilation, compression-only mode and handover; expected posterior >=0.90.
- Isolated Godot APK executed 17 prefixes via ccbm_native.gd on Quest 3: PASS.
  Measured application request time: approximately 27–42 ms, not full speech latency.
- GDScript regression tests validate posterior parsing and reset/concurrency
  handling separately; held transports are explicitly not inference tests.
- Final training microphone/voice/XR session is a separate end-to-end check.

## Upstream licensing

CCBM's upstream license is CC BY-NC-SA 4.0, included as UPSTREAM_LICENSE.txt in
the addon and APK runtime assets. This port is not commercial-use permission.
Upstream source: https://github.com/vac-mmis/CCBMpublic
Adapter source/build recipe are adjacent; no proprietary substitute is hidden.
