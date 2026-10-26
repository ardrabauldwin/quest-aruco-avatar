"""Exercise production HTTP framing without loading CUDA or a Whisper model."""
import ast
import json
import socket
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace


class HTTPConnectionTests(unittest.TestCase):
    def test_http11_response_closes_the_connection_after_its_body(self):
        source = ast.parse(Path(__file__).with_name('local_gpu_asr_server.py').read_text())
        handler = next(node for node in source.body if isinstance(node, ast.ClassDef) and node.name == 'Handler')
        namespace = dict(BaseHTTPRequestHandler=BaseHTTPRequestHandler, json=json,
                         args=SimpleNamespace(model='test', vocabulary_hints=False))
        exec(compile(ast.Module(body=[handler], type_ignores=[]), 'production_handler', 'exec'), namespace)
        server = ThreadingHTTPServer(('127.0.0.1', 0), namespace['Handler'])
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for _ in range(3):
                with socket.create_connection(server.server_address, timeout=2) as client:
                    client.sendall(b'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n')
                    response = b''
                    while True:
                        chunk = client.recv(4096)
                        if not chunk:
                            break
                        response += chunk
                headers, body = response.split(b'\r\n\r\n', 1)
                self.assertIn(b'Connection: close', headers)
                self.assertTrue(json.loads(body)['ready'])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == '__main__':
    unittest.main()
