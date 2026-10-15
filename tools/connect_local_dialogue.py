"""Enable the tested local conversation service without touching calibration."""
import json
from connect_local_speech import run, write_verified

if __name__ == '__main__':
    config = json.loads(run(['exec-out', 'run-as', 'de.uni_greifswald.naret.cprwitness', 'cat', 'files/config.json']))
    config.setdefault('api', {})['local_ai_url'] = 'http://127.0.0.1:8768'
    write_verified('files/config.json', (json.dumps(config) + '\n').encode())
    run(['reverse', 'tcp:8768', 'tcp:8768'])
    print('Local dialogue and distinct voices enabled; calibration preserved.')
