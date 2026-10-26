"""Recovery policy for the USB-local speech bridge; no headset state changes."""
import subprocess


def quest_usb_present():
    # Meta's vendor ID was verified on the attached Quest. Avoid resetting ADB
    # merely because an unrelated phone or no USB device is attached.
    command = "Get-CimInstance Win32_PnPEntity -Filter \"Name='ADB Interface'\" | Select-Object -ExpandProperty PNPDeviceID"
    try:
        result = subprocess.run(["powershell", "-NoProfile", "-Command", command],
                                capture_output=True, text=True, timeout=15)
        return result.returncode == 0 and "VID_2833" in result.stdout.upper()
    except (OSError, subprocess.TimeoutExpired):
        return False


def should_recover(devices, missing_polls, seconds_since_reset, usb_present):
    return (missing_polls >= 2 and seconds_since_reset >= 20 and usb_present
            and "\tdevice" not in devices and "\tunauthorized" not in devices)


def speech_bridge_healthy(adb, serial):
    """Check the actual Quest-to-PC path, rather than the reverse-port listing."""
    command = "{ printf 'GET / HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n'; sleep 1; } | nc -w 2 127.0.0.1 8767"
    result = adb(['-s', serial, 'shell', command])
    return result.returncode == 0 and '200 OK' in result.stdout and '"ready": true' in result.stdout


def repair_speech_bridge(adb, serial):
    # Remove the stale listener even when `reverse --list` still reports it.
    # This leaves the running exercise and saved calibration untouched.
    adb(['-s', serial, 'reverse', '--remove', 'tcp:8767'])
    return adb(['-s', serial, 'reverse', 'tcp:8767', 'tcp:8767']).returncode == 0
