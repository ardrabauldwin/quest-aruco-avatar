"""Download the six selected Piper voices and their model cards."""
import json
import urllib.request
from local_dialogue_server import VOICES, VOICE_ROOT

if __name__ == '__main__':
    VOICE_ROOT.mkdir(parents=True, exist_ok=True)
    base = 'https://huggingface.co/rhasspy/piper-voices/resolve/main/'
    with urllib.request.urlopen(base + 'voices.json', timeout=30) as response:
        catalog = json.load(response)
    for name in VOICES.values():
        entry = catalog[name]
        for source in entry['files']:
            if source.endswith(('.onnx', '.onnx.json', 'MODEL_CARD')):
                filename = name + '-MODEL_CARD' if source.endswith('MODEL_CARD') else source.rsplit('/', 1)[-1]
                target = VOICE_ROOT / filename
                if not target.exists():
                    with urllib.request.urlopen(base + source, timeout=180) as response:
                        target.write_bytes(response.read())
        print('Ready:', name, flush=True)
