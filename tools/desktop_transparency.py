"""Small desktop editor for the connected Quest's patient transparency.

Only patient_opacity is changed. The marker alignment and floor settings are
preserved. Applying restarts the app because it reads calibration at startup.
"""
import re
import subprocess
from pathlib import Path
import tkinter as tk
from tkinter import messagebox

ADB = r"C:\Users\bauld\AppData\Local\Android\Sdk\platform-tools\adb.exe"
PACKAGE = "de.uni_greifswald.naret.cprwitness"
SERIAL = "2G0YC5ZH0G00HS"


def adb(*args, data=None):
    result = subprocess.run(
        [ADB, "-s", SERIAL, *args], input=data, capture_output=True,
        timeout=45, creationflags=subprocess.CREATE_NO_WINDOW,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace").strip())
    return result.stdout


def read_calibration():
    return adb("shell", "run-as", PACKAGE, "cat", "files/calibration.cfg")


def apply():
    try:
        original = read_calibration()
        # Back up the complete calibration before changing this one setting.
        backup = Path(__file__).resolve().parent.parent / "build" / "calibration-before-desktop-opacity.cfg"
        if not backup.exists():
            backup.write_bytes(original)
        text = original.decode("utf-8").replace("\r\n", "\n")
        opacity = 1.0 - transparency.get() / 100.0
        match = re.search(r"(?ms)^\[calibration\]\n(.*?)(?=^\[|\Z)", text)
        if not match:
            raise RuntimeError("No calibration section found; nothing was changed.")
        section = match.group(1)
        setting = f"patient_opacity={opacity:.4f}"
        if re.search(r"(?m)^patient_opacity\s*=", section):
            section = re.sub(r"(?m)^patient_opacity\s*=.*$", setting, section)
        else:
            section = section.rstrip() + "\n" + setting + "\n\n"
        updated = text[:match.start(1)] + section + text[match.end(1):]
        adb("shell", "run-as", PACKAGE, "sh", "-c",
            "'cat > files/calibration-opacity.tmp && mv files/calibration-opacity.tmp files/calibration.cfg'",
            data=updated.encode("utf-8"))
        if read_calibration().decode("utf-8").replace("\r\n", "\n") != updated:
            raise RuntimeError("Saved setting could not be verified.")
        adb("shell", "am", "force-stop", PACKAGE)
        adb("shell", "am", "start", "-n", f"{PACKAGE}/com.godot.game.GodotAppLauncher")
        status.set(f"Applied {transparency.get():.0f}% transparency. Headset app restarted.")
    except Exception as error:
        messagebox.showerror("Could not apply transparency", str(error))


root = tk.Tk()
root.title("Quest patient transparency")
root.geometry("560x260")
tk.Label(root, text="Patient transparency", font=("Segoe UI", 18)).pack(pady=14)
tk.Label(root, text="Body: 0% = opaque, 100% = invisible. Face stays solid.").pack()
transparency = tk.DoubleVar(value=25)
try:
    current = read_calibration().decode("utf-8")
    match = re.search(r"(?m)^patient_opacity\s*=\s*([0-9.]+)", current)
    if match:
        transparency.set((1.0 - float(match.group(1))) * 100.0)
except Exception as error:
    messagebox.showwarning("Headset setting", str(error))
tk.Scale(root, from_=0, to=100, resolution=5, orient="horizontal",
         variable=transparency, length=480).pack()
tk.Button(root, text="Apply to headset (restarts app)", command=apply,
          font=("Segoe UI", 12)).pack(pady=12)
status = tk.StringVar(value="Alignment and floor settings are preserved.")
tk.Label(root, textvariable=status, wraplength=520).pack()
root.mainloop()
