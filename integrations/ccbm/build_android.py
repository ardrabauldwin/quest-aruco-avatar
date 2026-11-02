"""Cross-compile the real generated CCBM filter and package an ARM64 runtime AAR.

Build-machine tooling only: run on Linux/WSL with an Android NDK and the pinned
CCBM upstream checkout. No compiler, Haskell or Python is needed on Quest.
"""
import argparse
import base64
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

PIN = "42672c8946e42447c370c6bf19a655c93965502b"
HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]


def run(args, **kwargs):
    subprocess.run([str(x) for x in args], check=True, timeout=300, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--upstream", type=Path, default=Path("/opt/naret-ccbm"))
    parser.add_argument("--states", type=Path, required=True,
                        help="State table generated from the same PDDL model")
    parser.add_argument("--build", type=Path, default=Path("/opt/naret-android/ccbm-build"))
    args = parser.parse_args()
    revision = subprocess.check_output(["git", "-C", str(args.upstream), "rev-parse", "HEAD"], timeout=30).decode().strip()
    if revision != PIN:
        raise SystemExit("Unexpected upstream revision; review before changing the pin")
    args.build.mkdir(parents=True, exist_ok=True)
    generated = args.build / "generated"
    generated.mkdir(exist_ok=True)
    # Generation remains on the build machine. Outputs are compiled for Android.
    run([args.upstream / "rc", "-c", "-W", "-M", "FA", "-n", "1000",
         "-d", HERE / "d.pddl", "-p", HERE / "p.pddl", "-o", HERE / "d-observations",
         "-w", generated, "-f", args.build / "p", "-C", "-DUSE_ACTION_ESTIMATION"], cwd=args.build)
    source = args.upstream / "src"
    toolchain = args.ndk / "toolchains/llvm/prebuilt/linux-x86_64"
    clang = toolchain / "bin/aarch64-linux-android29-clang"
    cxx = toolchain / "bin/aarch64-linux-android29-clang++"
    includes = ["-I" + str(args.build), "-I" + str(source), "-I" + str(source / "lib"),
                "-isystem", str(source / "lib/boost"), "-I" + str(source / "lib/fann/src/include")]
    defines = [f"-D{name}=<{path}>" for name, path in {
        "MODEL_HEADER": generated / "p-model.h", "MODEL_HEADER_DEFINES": generated / "p-model-defines.h",
        "MODEL_IMPL": generated / "p-model.cpp", "FILTER_PARAMETERS": generated / "_rcparams.h",
        "OBSERVATION_MODEL_HEADER": HERE / "d-observations.h",
        "OBSERVATION_MODEL_IMPL": HERE / "d-observations.cpp"}.items()]
    common = ["-O2", "-fPIE", "-ffunction-sections", "-fdata-sections", "-DNVALGRIND", "-DUSE_ACTION_ESTIMATION"]
    units = [(source / x, x.replace("/", "_") + ".o", []) for x in [
        "obsmodel.cpp", "duration.cpp", "util/allocator.cpp", "util/parameter.cpp",
        "model.cpp", "global.cpp", "state.cpp", "stateFunctions.cpp", "heuristics.cpp"]]
    units += [(source / "main.cpp", "main.o", ["-Dmain=naret_ccbm_original_main"]),
              (HERE / "android_main.cpp", "adapter.o", []),
              (source / "lib/boost/libs/iostreams/src/gzip.cpp", "gzip.o", []),
              (source / "lib/boost/libs/iostreams/src/zlib.cpp", "zlib.o", [])]

    def compile_unit(unit):
        src, name, extra = unit
        obj = args.build / name
        run([cxx, "-std=c++11", *common, *includes, *defines, *extra, "-c", src, "-o", obj], cwd=args.build)
        return obj

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        objects = list(pool.map(compile_unit, units))
    fann = args.build / "floatfann.o"
    run([clang, "-O2", "-fPIE", "-ffunction-sections", "-fdata-sections", "-I" + str(source / "lib/fann/src/include"), "-c",
         source / "lib/fann/src/floatfann.c", "-o", fann])
    executable = args.build / "libnaret_ccbm.so"
    # This is a PIE executable packaged under the Android native-library naming
    # convention, executed from nativeLibraryDir, never dlopen'ed as a library.
    run([cxx, "-pie", "-static-libstdc++", "-Wl,--gc-sections", "-Wl,-z,max-page-size=16384", *objects, fann, "-lz", "-o", executable])
    run([toolchain / "bin/llvm-strip", "--strip-unneeded", executable])
    target = PROJECT / "addons/ccbm_native"
    target.mkdir(parents=True, exist_ok=True)
    license_text = (args.upstream / "LICENSE").read_bytes()
    (target / "UPSTREAM_LICENSE.txt").write_bytes(license_text)
    dependency_notices = {
        "BOOST_LICENSE.txt": source / "lib/boost/LICENSE_1_0.txt",
        "FANN_LICENSE.txt": source / "lib/fann/LICENSE.md",
    }
    for name, path in dependency_notices.items():
        (target / name).write_bytes(path.read_bytes())
    with zipfile.ZipFile(target / "naret_ccbm_runtime.aar", "w", zipfile.ZIP_DEFLATED) as aar:
        aar.writestr("AndroidManifest.xml", '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="de.uni_greifswald.naret.ccbm"><uses-sdk android:minSdkVersion="29"/></manifest>')
        classes = io.BytesIO()
        with zipfile.ZipFile(classes, "w"): pass
        aar.writestr("classes.jar", classes.getvalue())
        aar.write(executable, "jni/arm64-v8a/libnaret_ccbm.so")
        aar.writestr("assets/ccbm_UPSTREAM_LICENSE.txt", license_text)
        for name, path in dependency_notices.items():
            aar.writestr("assets/ccbm_" + name, path.read_bytes())
    model = {"engine": "ccbm", "upstream_revision": revision,
             "domain_sha256": hashlib.sha256((HERE / "d.pddl").read_bytes().replace(b"\r\n", b"\n")).hexdigest(),
             "states_sha256": hashlib.sha256(args.states.read_bytes()).hexdigest(),
             "states_base64": base64.b64encode(args.states.read_bytes()).decode(),
             "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest()}
    (target / "model.json").write_text(json.dumps(model, indent=2) + "\n")
    print("ANDROID_CCBM_BUILT", executable.stat().st_size, "bytes", flush=True)


if __name__ == "__main__":
    main()
