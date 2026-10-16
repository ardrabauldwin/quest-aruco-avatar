"""Exercise real local model/voices; save no user recordings."""
import json
import time
import urllib.request
from pathlib import Path
from local_dialogue_server import VOICES

def post(path, body):
    request = urllib.request.Request('http://127.0.0.1:8768' + path, data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()

if __name__ == '__main__':
    started = time.monotonic()
    result = json.loads(post('/chat/completions', {'messages': [
        {'role': 'system', 'content': 'You are Anna in a CPR simulation. Your husband Jan collapsed. His age is unknown. Answer naturally in JSON with text,action none,language en. No medical coaching.'},
        {'role': 'user', 'content': 'Anna, what is his name?'}]}))
    reply = json.loads(result['choices'][0]['message']['content'])
    assert 'jan' in reply['text'].lower(), reply
    print('Anna context response passed, seconds:', round(time.monotonic()-started, 1), flush=True)
    # Established incident questions now use witness_fact_reply in Godot, tested
    # by test_training_coach.gd: an LLM must not invent a cause of the collapse.
    guide = json.loads((Path(__file__).resolve().parents[1] / 'data/coach_steps.json').read_text(encoding='utf-8'))['en']
    result = json.loads(post('/chat/completions', {'messages': [
        {'role': 'system', 'content': 'You are a supportive CPR instructor. Only use approved guidance. Do not claim actions completed. Answer the question in JSON with text (maximum 360 characters), action none, language en.'},
        {'role': 'user', 'content': json.dumps({'approved_guide': guide, 'next_step': 'compressions', 'question': 'How deep should I press and how fast?'})}]}))
    reply = json.loads(result['choices'][0]['message']['content'])
    assert reply['action'] == 'none' and reply['language'] == 'en' and len(reply['text']) <= 360, reply
    assert '100' in reply['text'] and '120' in reply['text'] and '5' in reply['text'] and '6' in reply['text'], reply
    print('Instructor approved guidance response passed.', flush=True)
    rendered = {}
    for language, speaker in VOICES:
        audio = post('/audio/speech', {'input': {'en': 'Please check whether he responds.', 'de': 'Bitte prüfen Sie, ob er reagiert.', 'pl': 'Sprawdź, czy reaguje.'}[language], 'language': language, 'speaker': speaker})
        assert audio[:4] == b'RIFF' and len(audio) > 1000
        rendered[(language, speaker)] = audio
        print('Voice passed:', language, speaker, len(audio), flush=True)
    for language in ('en', 'de', 'pl'):
        assert rendered[(language, 'bystander')] != rendered[(language, 'instructor')]
    print('All six voice outputs are valid; roles have distinct models.')
