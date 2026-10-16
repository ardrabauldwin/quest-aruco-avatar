#!/usr/bin/env python3
"""Provision NaReT's private Godot configuration on one installed debug Quest app.

Online:  python3 tools/configure_quest.py [--serial SERIAL]
Preview: python3 tools/configure_quest.py --dry-run
Remove this config's credential and force offline: add --offline.

No credential appears in command arguments, output, the APK, or local temp files.
The secret is transferred only as stdin to adb exec-in / run-as. Existing unrelated
config fields are preserved; calibration and session files are never touched.

Godot Android resolves user:// directly to Context.getFilesDir(), not app_userdata:
https://github.com/godotengine/godot/blob/4.5/platform/android/java_godot_io_wrapper.cpp#L111
https://github.com/godotengine/godot/blob/4.5/platform/android/java/lib/src/org/godotengine/godot/GodotIO.java#L151
"""
from __future__ import annotations

import argparse
import copy
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys

from api_common import BASE_URL, MODELS, read_key

PACKAGE = "de.uni_greifswald.naret.cprwitness"
CONFIG_PATH = "files/config.json"
MAX_CONFIG_BYTES = 256 * 1024


class ProvisionError(Exception):
    """Messages are authored locally and never contain remote response bodies."""


def build_config(existing: dict, *, offline: bool, key: str = "") -> dict:
    result = copy.deepcopy(existing)
    api = result.setdefault("api", {})
    if not isinstance(api, dict):
        raise ProvisionError("Existing config has a non-object api section; refusing to overwrite it.")
    # The runtime also accepts flat config files. Remove a legacy flat credential.
    result.pop("api_key", None)
    if offline:
        api.pop("api_key", None)
        api["offline"] = True
    else:
        if not key or any(character in key for character in "\r\n\x00"):
            raise ProvisionError("No valid UNI_API_KEY/API_SECRET found in environment or root .env.")
        api.update({
            "base_url": BASE_URL,
            "api_key": key,
            "asr_model": MODELS["asr"],
            "tts_model": MODELS["tts"],
            "tts_voice": "",
            "llm_model": MODELS["llm"],
            "timeout_s": 2,
            "offline": False,
            "offline_fallback": True,
        })
    return result


class ADB:
    def __init__(self, executable: str, serial: str | None):
        self.command = [executable]
        if serial:
            self.command += ["-s", serial]
        self.environment = os.environ.copy()
        # Prevent client packet tracing or inherited application credentials.
        for name in ("ADB_TRACE", "UNI_API_KEY", "API_SECRET"):
            self.environment.pop(name, None)

    def run(self, arguments: list[str], *, payload: bytes | None = None,
            purpose: str, allow_failure: bool = False) -> subprocess.CompletedProcess:
        try:
            result = subprocess.run(self.command + arguments, input=payload,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    env=self.environment, timeout=20, check=False)
        except subprocess.TimeoutExpired:
            raise ProvisionError(f"ADB timed out while {purpose}.") from None
        except OSError:
            raise ProvisionError("ADB could not be started. Set --adb or install Android platform-tools.") from None
        if result.returncode and not allow_failure:
            # Do not print raw stdout/stderr, which may include private config data.
            raise ProvisionError(f"ADB failed while {purpose} (exit {result.returncode}). Check device authorization and an installed debuggable NaReT APK.")
        return result

    def app(self, arguments: list[str], *, payload: bytes | None = None,
            purpose: str, allow_failure: bool = False) -> subprocess.CompletedProcess:
        transport = "exec-in" if payload is not None else "exec-out"
        return self.run([transport, "run-as", PACKAGE] + arguments,
                        payload=payload, purpose=purpose, allow_failure=allow_failure)

    def sh(self, arguments: list[str], *, purpose: str,
           allow_failure: bool = False) -> subprocess.CompletedProcess:
        """Run a device command whose exit status matters.

        exec-in/exec-out report adb's own status, never the remote command's, so
        every test and mkdir there looks successful. Only `adb shell` forwards it.
        Binary output is unusable here, so data reads stay on exec-out.
        """
        return self.run(["shell", "run-as", PACKAGE] + arguments,
                        purpose=purpose, allow_failure=allow_failure)


def read_existing(adb: ADB) -> dict:
    exists = adb.sh(["test", "-e", CONFIG_PATH], purpose="checking existing config", allow_failure=True)
    if exists.returncode == 1:
        return {}
    if exists.returncode:
        raise ProvisionError("Unable to check existing private config.")
    regular = adb.sh(["test", "-f", CONFIG_PATH], purpose="checking config file type", allow_failure=True)
    symlink = adb.sh(["test", "-L", CONFIG_PATH], purpose="checking config symlink", allow_failure=True)
    if regular.returncode != 0 or symlink.returncode == 0:
        raise ProvisionError("Private config must be a regular, non-symlink file.")
    raw = adb.app(["cat", CONFIG_PATH], purpose="reading existing config privately").stdout
    if len(raw) > MAX_CONFIG_BYTES:
        raise ProvisionError("Existing config is unexpectedly large; refusing to overwrite it.")
    try:
        data = json.loads(raw)
    except (ValueError, UnicodeError):
        raise ProvisionError("Existing config is invalid JSON; refusing to overwrite it.") from None
    if not isinstance(data, dict):
        raise ProvisionError("Existing config is not a JSON object; refusing to overwrite it.")
    return data


def provision(adb: ADB, *, offline: bool, key: str) -> str:
    adb.run(["get-state"], purpose="checking the connected device")
    location = adb.app(["pwd"], purpose="locating the installed debug application's private directory").stdout.decode("utf-8", errors="replace").strip()
    pattern = r"/data/(?:user/\d+|data)/" + re.escape(PACKAGE)
    if re.fullmatch(pattern, location) is None:
        raise ProvisionError("run-as returned an unexpected app-private path; no config was written.")
    # Reject redirection out of the app sandbox via a substituted files symlink.
    linked = adb.sh(["test", "-L", "files"], purpose="checking the private files directory", allow_failure=True)
    if linked.returncode == 0:
        raise ProvisionError("App files directory is a symlink; refusing to provision a secret there.")
    adb.sh(["mkdir", "-p", "files"], purpose="creating Godot's private user directory")
    config = build_config(read_existing(adb), offline=offline, key=key)
    payload = (json.dumps(config, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if len(payload) > MAX_CONFIG_BYTES:
        raise ProvisionError("Merged config exceeds the allowed size.")
    staging = "files/.naret-config-" + secrets.token_hex(12)
    temporary = staging + "/config.json"
    adb.sh(["mkdir", "-m", "700", staging], purpose="creating a private staging directory")
    try:
        # Create with mode 0600 before any credential bytes are transmitted.
        adb.sh(["touch", temporary], purpose="creating the private config file")
        adb.sh(["chmod", "600", temporary], purpose="restricting config permissions")
        # toybox dd reads nothing from an exec-in pipe and leaves the file empty.
        adb.app(["tee", temporary], payload=payload, purpose="sending config over stdin")
        staged = adb.app(["cat", temporary], purpose="verifying staged config privately").stdout
        if not hmac.compare_digest(staged, payload):
            raise ProvisionError("Staged config verification failed; existing config was left unchanged.")
        adb.sh(["mv", "-f", temporary, CONFIG_PATH], purpose="atomically replacing this app's config")
        installed = adb.app(["cat", CONFIG_PATH], purpose="verifying installed config privately").stdout
        if not hmac.compare_digest(installed, payload):
            raise ProvisionError("Installed config verification failed.")
        mode = adb.app(["stat", "-c", "%a", CONFIG_PATH], purpose="verifying private permissions").stdout.strip()
        if mode != b"600":
            raise ProvisionError("Installed config permissions differ from the required 0600.")
    finally:
        # Restrict cleanup to this invocation's random staging file and directory.
        adb.sh(["rm", "-f", temporary], purpose="cleaning the staged config", allow_failure=True)
        adb.sh(["rmdir", staging], purpose="removing the empty staging directory", allow_failure=True)
    return location + "/" + CONFIG_PATH


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--serial", help="ADB device serial; required if multiple devices are connected")
    parser.add_argument("--adb", help="Path to adb; defaults to PATH or the Android SDK")
    parser.add_argument("--dry-run", action="store_true", help="Validate local configuration only; never contact or write to a device")
    parser.add_argument("--offline", action="store_true", help="Remove the credential from this config and force offline mode")
    args = parser.parse_args(argv)
    try:
        key = "" if args.offline else read_key()
        build_config({}, offline=args.offline, key=key)  # Local validation, no output.
        if args.dry_run:
            print(f"Dry run: {PACKAGE}; target <app-private>/files/config.json; mode {'offline (remove credential)' if args.offline else 'online'}.")
            print("No device contacted. JSON and credentials are withheld; writes use stdin and mode 0600.")
            return 0
        sdk = Path(os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or Path.home() / "Library/Android/sdk")
        executable = args.adb or shutil.which("adb") or str(sdk / "platform-tools/adb")
        location = provision(ADB(executable, args.serial), offline=args.offline, key=key)
        print(f"Verified {'offline' if args.offline else 'online'} configuration: {location} (mode 0600).")
        print("Restart NaReT to apply. No credential was printed or embedded in the APK.")
        return 0
    except ProvisionError as error:
        print(f"Configuration failed: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Configuration interrupted.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
