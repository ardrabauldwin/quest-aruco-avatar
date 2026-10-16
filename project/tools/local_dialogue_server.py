"""USB-local Ollama dialogue and Piper speech. No cloud key or transcript logs.

Run in Ubuntu with the Piper virtual environment. Bind loopback only; adb reverse
exposes this service to the attached Quest, rather than to the local network.
"""
import io
import json
import os
import threading
import urllib.request
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VOICE_ROOT = Path(os.environ.get('NARET_VOICES', '/opt/naret-dialogue/voices'))
MODEL = os.environ.get('NARET_CHAT_MODEL', 'qwen3:4b-instruct')
INTERPRETER_URL = os.environ.get('NARET_INTERPRETER_URL', '')
VOICES = {
    ('en', 'bystander'): 'en_US-lessac-medium',
    ('en', 'instructor'): 'en_US-ryan-medium',
    ('de', 'bystander'): 'de_DE-kerstin-low',
    ('de', 'instructor'): 'de_DE-thorsten-medium',
    ('pl', 'bystander'): 'pl_PL-gosia-medium',
    ('pl', 'instructor'): 'pl_PL-darkman-medium',
}
_voices = {}
_speech_lock = threading.Lock()
_chat_lock = threading.Lock()

def chat(payload):
    messages = payload.get('messages')
    if not isinstance(messages, list) or not 1 <= len(messages) <= 16:
        raise ValueError('Invalid messages')
    for message in messages:
        if not isinstance(message, dict) or message.get('role') not in ('system', 'user', 'assistant') or not isinstance(message.get('content'), str) or len(message['content']) > 20000:
            raise ValueError('Invalid message')
    # Use the same two bounded contracts as Godot. JSON mode alone can omit keys.
    observation = messages[0]['content'].startswith('Classify one trainee utterance')
    if observation and INTERPRETER_URL == 'http://127.0.0.1:8771':
        # The app wraps utterances in JSON; the adapter was trained on plain text.
        user = next((item['content'] for item in reversed(messages) if item['role']=='user'), '')
        parsed = json.loads(user)
        if not isinstance(parsed,dict) or not isinstance(parsed.get('utterance'),str):
            raise ValueError('Invalid observation input')
        request = urllib.request.Request(INTERPRETER_URL+'/classify',
            data=json.dumps({'utterance':parsed['utterance']}).encode(),
            headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=20) as response:
            result=json.load(response)
        return {'choices':[{'message':{'role':'assistant','content':json.dumps(result,ensure_ascii=False)}}]}
    properties = ({
        'action': {'type': 'string', 'enum': ['begin_check', 'check_responsiveness', 'call_emergency', 'check_breathing', 'ventilation', 'compression_only', 'handover', 'none']},
        'kind': {'type': 'string', 'enum': ['report', 'request', 'question', 'intention', 'uncertain', 'conversation']},
        'result': {'type': 'string', 'enum': ['safe', 'unresponsive', 'responsive', 'abnormal', 'normal', 'one_breath', 'none']},
        'evidence': {'type': 'string', 'maxLength': 1000},
    } if observation else {
        'text': {'type': 'string', 'maxLength': 360},
        'action': {'type': 'string', 'enum': ['calm', 'call_help', 'fetch_aed', 'thank', 'none']},
        'language': {'type': 'string', 'enum': ['en', 'de', 'pl']},
    })
    schema = {'type': 'object', 'properties': properties, 'required': list(properties), 'additionalProperties': False}
    request = urllib.request.Request('http://127.0.0.1:11434/api/chat',
        data=json.dumps({'model': MODEL, 'messages': messages, 'stream': False,
                         'format': schema, 'think': False,
                         'options': {'temperature': 0.35, 'num_predict': 220, 'num_ctx': 4096}}).encode(),
        headers={'Content-Type': 'application/json'})
    with _chat_lock, urllib.request.urlopen(request, timeout=40) as response:
        result = json.load(response)
    return {'choices': [{'message': {'role': 'assistant', 'content': result['message']['content']}}]}

def speech(payload):
    from piper import PiperVoice
    text = payload.get('input')
    key = (payload.get('language'), payload.get('speaker'))
    if not isinstance(text, str) or not 1 <= len(text) <= 1000 or key not in VOICES:
        raise ValueError('Invalid speech input')
    with _speech_lock:
        if key not in _voices:
            _voices[key] = PiperVoice.load(str(VOICE_ROOT / (VOICES[key] + '.onnx')))
        output = io.BytesIO()
        with wave.open(output, 'wb') as wav:
            _voices[key].synthesize_wav(text, wav)
        return output.getvalue()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass  # Never log spoken words or request bodies.

    def send(self, code, body, content_type='application/json'):
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != '/health':
            self.send(404, b'{}')
            return
        missing = [name for name in VOICES.values() if not (VOICE_ROOT / (name + '.onnx')).exists()]
        self.send(200, json.dumps({'service': 'local_dialogue', 'model': MODEL, 'interpreter': INTERPRETER_URL or 'ollama_default', 'missing_voices': missing}).encode())

    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 65536:
                raise ValueError('Invalid length')
            payload = json.loads(self.rfile.read(length))
            if not isinstance(payload, dict):
                raise ValueError('Invalid payload')
            if self.path == '/chat/completions':
                self.send(200, json.dumps(chat(payload)).encode())
            elif self.path == '/audio/speech':
                self.send(200, speech(payload), 'audio/wav')
            else:
                self.send(404, b'{}')
        except (ValueError, TypeError, json.JSONDecodeError):
            self.send(400, b'{"error":"invalid_request"}')
        except Exception:
            self.send(503, b'{"error":"local_service_unavailable"}')

if __name__ == '__main__':
    print('Local dialogue and speech: 127.0.0.1:8768', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 8768), Handler).serve_forever()
