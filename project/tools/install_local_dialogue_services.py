"""Run in WSL as root: keep dialogue and CCBM alive without a terminal timeout."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
services = {
    'naret-dialogue': ['/opt/naret-dialogue/bin/python', str(root / 'tools/local_dialogue_server.py')],
    'naret-ccbm': ['/usr/bin/python3', str(root / 'integrations/ccbm/server.py')],
    'naret-asr': ['/bin/bash', str(root / 'tools/start_local_asr.sh')],
}
for name, command in services.items():
    # This workspace has no spaces; quote each argument for systemd nonetheless.
    executable = ' '.join('"' + arg + '"' for arg in command)
    Path('/etc/systemd/system/' + name + '.service').write_text(
        '[Unit]\nDescription=NaReT local training service\nAfter=network.target\n'
        '[Service]\nType=simple\nExecStart=' + executable + '\n'
        'Restart=on-failure\nRestartSec=3\n'
        '[Install]\nWantedBy=multi-user.target\n')
subprocess.run(['systemctl', 'daemon-reload'], check=True, timeout=20)
subprocess.run(['systemctl', 'enable', '--now', *[name + '.service' for name in services]], check=True, timeout=30)
print('Dialogue and CCBM are managed services with automatic restart.')
