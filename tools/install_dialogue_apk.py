"""Update the attached Quest and verify the saved calibration is byte-identical."""
from pathlib import Path
import hashlib
import subprocess
from connect_local_speech import PREFIX, PACKAGE, run

if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    calibration = run(['exec-out', 'run-as', PACKAGE, 'cat', 'files/calibration.cfg'])
    backup = root / 'build/private-calibration-before-dialogue.cfg'
    backup.write_bytes(calibration)
    result = subprocess.run(PREFIX + ['install', '-r', str(root / 'build/naret-natural-coach-20261009.apk')], capture_output=True, text=True, timeout=180)
    if result.returncode or 'Success' not in result.stdout:
        raise RuntimeError('APK update failed: ' + result.stderr)
    after = run(['exec-out', 'run-as', PACKAGE, 'cat', 'files/calibration.cfg'])
    if hashlib.sha256(after).digest() != hashlib.sha256(calibration).digest():
        raise RuntimeError('Saved calibration changed unexpectedly; backup retained')
    print('APK installed; saved calibration verified unchanged.')
    # Reconnects can discard reverse mappings; restore before app launch.
    for port in (8766, 8767, 8768):
        run(['reverse', f'tcp:{port}', f'tcp:{port}'])
    print('USB forwarding restored for speech, dialogue and CCBM.')
    run(['shell', 'am', 'force-stop', PACKAGE])
    launch = subprocess.run(PREFIX + ['shell', 'monkey', '-p', PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1'], capture_output=True, text=True, timeout=20)
    if launch.returncode:
        raise RuntimeError('Installed successfully, but automatic launch failed')
    print('App launched on Quest. Physical headset interaction still needs a user test.')
