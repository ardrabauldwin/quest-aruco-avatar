"""Local interactive token entry. Never print or pass credentials as arguments."""
from pathlib import Path
import os
import re
import tkinter as tk
from tkinter import messagebox

ROOT = Path(__file__).resolve().parents[1]


def main():
    window = tk.Tk()
    window.title("NaReT — save AppHub API token locally")
    window.geometry("650x300")
    window.attributes("-topmost", True)
    frame = tk.Frame(window, padx=24, pady=22)
    frame.pack(fill="both", expand=True)
    tk.Label(frame, text="Paste your AppHub API token", font=("Segoe UI", 16, "bold")).pack(anchor="w")
    tk.Label(frame, text="Copy the token from AppHub's API Token page — not your university password.",
             wraplength=590, justify="left", font=("Segoe UI", 10)).pack(anchor="w", pady=(10, 15))
    entry = tk.Entry(frame, show="*", font=("Segoe UI", 13))
    entry.pack(fill="x")
    tk.Label(frame, text="Saved only in this project's Git-ignored .env file.\nThe token is not embedded in the APK or sent through chat.",
             justify="left", font=("Segoe UI", 10)).pack(anchor="w", pady=12)

    def save():
        token = entry.get().strip()
        if not token or any(ch.isspace() for ch in token) or any(ch in token for ch in ['"', "'", "\x00"]):
            messagebox.showerror("Token not saved", "Paste one API token without quotes, spaces or line breaks.", parent=window)
            return
        target = ROOT / ".env"
        staging = ROOT / ".env.naret-pending"
        try:
            content = target.read_text(encoding="utf-8") if target.exists() else ""
            lines = [line for line in content.splitlines()
                     if not re.match(r"^\s*(?:export\s+)?UNI_API_KEY\s*=", line)]
            lines.append("UNI_API_KEY=" + token)
            fd = os.open(staging, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
                stream.write("\n".join(lines) + "\n")
            os.replace(staging, target)
        except OSError:
            messagebox.showerror("Token not saved", "Could not save the local configuration file. No token was printed.", parent=window)
            return
        entry.delete(0, tk.END)
        messagebox.showinfo("Saved locally", "Token saved. Return to chat and say 'saved'.\nThe headset connection still needs to be configured and tested.", parent=window)
        window.destroy()

    tk.Button(frame, text="Save token locally", command=save, font=("Segoe UI", 11), padx=14, pady=7).pack(anchor="w")
    entry.focus_set()
    window.mainloop()


if __name__ == "__main__":
    main()
