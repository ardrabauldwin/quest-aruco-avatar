"""Exercise the real upload handler without loading GPU weights or starting a server."""
import ast
import io
import json
from email import policy
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler
from pathlib import Path
import threading
import time
from types import SimpleNamespace
import unittest


class PromptTransportTest(unittest.TestCase):
    def test_gpu_handler_passes_prompt_to_decoder(self):
        tree = ast.parse(Path(__file__).with_name("local_gpu_asr_server.py").read_text())
        handler = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "Handler")
        calls = []

        def transcribe(audio, **kwargs):
            self.assertEqual(audio.read(), b"audio bytes")
            calls.append(kwargs)
            return [SimpleNamespace(text="decoded speech")], None

        scope = dict(BaseHTTPRequestHandler=BaseHTTPRequestHandler, BytesParser=BytesParser,
                     policy=policy, io=io, json=json, time=time, lock=threading.Lock(),
                     model=SimpleNamespace(transcribe=transcribe), VOCABULARY={},
                     args=SimpleNamespace(vocabulary_hints=False))
        exec(compile(ast.Module(body=[handler], type_ignores=[]), "gpu_handler", "exec"), scope)
        for language, prompt in [("en", "rescue breaths"), ("de", "Beatmung"),
                                 ("pl", "oddechy ratownicze"), ("en", ""), ("en", "x" * 513)]:
            fields = {"language": language.encode(), "prompt": prompt.encode(), "file": b"audio bytes"}
            body = b"".join(b'--test\r\nContent-Disposition: form-data; name="' + key.encode() +
                            b'"\r\n\r\n' + value + b'\r\n' for key, value in fields.items()) + b"--test--\r\n"
            replies = []
            request = SimpleNamespace(path="/inference", headers={"Content-Length": str(len(body)),
                "Content-Type": "multipart/form-data; boundary=test"}, rfile=io.BytesIO(body),
                connection=SimpleNamespace(settimeout=lambda _: None), reply=lambda code, result: replies.append((code, result)))
            before = len(calls)
            scope["Handler"].do_POST(request)
            if len(prompt) > 512:
                self.assertEqual(replies[0][0], 400)
                self.assertEqual(len(calls), before)
            else:
                self.assertEqual(replies[0][0], 200)
                self.assertEqual(calls[-1]["initial_prompt"], prompt or None)
                self.assertEqual(calls[-1]["language"], language)
                self.assertFalse(calls[-1]["condition_on_previous_text"])


if __name__ == "__main__":
    unittest.main()
