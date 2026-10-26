"""Loopback-only GPU Whisper endpoint, compatible with Quest /inference uploads.
No transcripts or audio are written to disk. One GPU inference runs at a time.
"""
import argparse
import io
import json
import threading
import time
from email import policy
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from faster_whisper import WhisperModel
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=18767)
parser.add_argument("--model", default="turbo")
parser.add_argument("--vocabulary-hints", action="store_true")
args = parser.parse_args()
VOCABULARY = {
    "en": "CPR, rescue breath, rescue breaths, breathing, chest compressions, airway",
    "de": "Reanimation, Beatmung, Beatmungen, Atmung, Herzdruckmassage, Atemwege",
    "pl": "resuscytacja, oddech ratowniczy, oddechy ratownicze, oddychanie, uciski klatki piersiowej",
}
model = WhisperModel(args.model, device="cuda", compute_type="float16", cpu_threads=4,
                     num_workers=1, download_root="/opt/naret-local-asr/gpu-models")
lock = threading.Lock()
# Load CUDA kernels before accepting the headset's first spoken report.
warmup, _ = model.transcribe(np.zeros(16000, dtype=np.float32), language="en", beam_size=5,
    temperature=0.0, condition_on_previous_text=False, vad_filter=False)
list(warmup)

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def setup(self):
        super().setup()
        # Each Godot request uses a new connection. Bound abandoned connections
        # even when a USB interruption happens before the HTTP headers arrive.
        self.connection.settimeout(20)

    def log_message(self, *_):
        pass

    def reply(self, code, data):
        body = json.dumps(data).encode()
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.close_connection = True
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        self.reply(200, {"ready": True, "backend": "faster-whisper", "model": args.model, "device": "cuda",
                         "vocabulary_hints": args.vocabulary_hints})

    def do_POST(self):
        if self.path != "/inference":
            return self.reply(404, {"error": "unknown_endpoint"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            print(json.dumps({"event": "upload_started", "bytes": length}), flush=True)
            if not 0 < length <= 4 * 1024 * 1024:
                return self.reply(413, {"error": "invalid_upload_size"})
            self.connection.settimeout(20)
            raw = self.rfile.read(length)
            message = BytesParser(policy=policy.default).parsebytes(
                ("Content-Type: " + self.headers.get("Content-Type", "") + "\r\nMIME-Version: 1.0\r\n\r\n").encode() + raw)
            fields = {}
            for part in message.iter_parts():
                fields[part.get_param("name", header="content-disposition")] = part.get_payload(decode=True)
            audio = fields.get("file")
            if not audio:
                return self.reply(400, {"error": "missing_audio"})
            language = fields.get("language", b"auto").decode().strip()
            if language not in ("en", "de", "pl", "auto", ""):
                return self.reply(400, {"error": "unsupported_language"})
            if not lock.acquire(timeout=3):
                return self.reply(429, {"error": "recognizer_busy"})
            try:
                started = time.monotonic()
                segments, _ = model.transcribe(io.BytesIO(audio), language=None if language in ("", "auto") else language,
                    beam_size=5, temperature=0.0, condition_on_previous_text=False, vad_filter=False,
                    hotwords=VOCABULARY.get(language) if args.vocabulary_hints else None)
                text = " ".join(segment.text.strip() for segment in segments).strip()
                elapsed_ms = round((time.monotonic() - started) * 1000)
                print(json.dumps({"event": "transcription", "duration_ms": elapsed_ms, "audio_bytes": len(audio), "language": language}), flush=True)
                self.reply(200, {"text": text, "duration_ms": elapsed_ms})
            finally:
                lock.release()
        except Exception as error:
            print(json.dumps({"event": "error", "kind": type(error).__name__}), flush=True)
            self.reply(500, {"error": type(error).__name__})

print("GPU ASR ready on loopback port " + str(args.port), flush=True)
ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
