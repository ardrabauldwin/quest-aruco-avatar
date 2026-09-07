# Quest APK rollback backup

Saved on 2026-09-07 at 20:38 Europe/Berlin, before installing the hand-motion practice update.

- Device: Quest 3, serial `2G0YC5ZH0G00HS`.
- Package: `de.unigreifswald.opencvaruco`.
- `previous_installed.apk`: exact APK pulled from the headset before the update.
- `previous_local_build.apk`: the previous local APK; its checksum matches the installed APK.
- SHA-256 for both: `FB0177EABFB0BBC0C60E7C794DC0304881B719B515D2579DED878AAB1F51FC11`.
- `updated_hand_tracking.apk`: the new hand-motion counter, practice HUD, and audio build,
  installed successfully with `adb install -r` on 2026-09-07.
- New APK SHA-256: `52E4F961D995788299771F66CECD7409DB549EC46DE18AE52D83F84D65DB0F79`.
- Post-install launch returned `Status: ok` for `com.godot.game.GodotApp`.

To restore later, connect the Quest with USB debugging authorized and run:

```powershell
& 'C:\Users\bauld\Overlay\quest-aruco-avatar\builds\quest_backup_20260907_203820\restore_previous.ps1'
```

The script checks the backup checksum and reinstalls with `adb install -r`, preserving current
app data. This is an APK backup, not a snapshot of calibration files or recordings.
If restore fails, it stops without uninstalling or deleting data.
