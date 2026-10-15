"""Small helpers shared by local tools. Never source .env or log credentials."""
from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_URL = "https://apphubai.wolke.uni-greifswald.de/v1"
MODELS = {"asr": "large-v3", "tts": "omnivoice", "llm": "unsloth/Qwen3.8-27B-GGUF:Q4_K_M", "embeddings": "qwen3-embedding:8b"}


def read_key(path: Path | None = None) -> str:
    """Read only expected names; .env is data, never executable shell code."""
    for name in ("UNI_API_KEY", "API_SECRET"):
        if os.environ.get(name):
            return os.environ[name].strip()
    values = {}
    env_path = path or ROOT / ".env"
    if env_path.is_file():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, value = line.removeprefix("export ").split("=", 1)
            if name.strip() in ("UNI_API_KEY", "API_SECRET"):
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                    value = value[1:-1]
                else:
                    value = value.split(" #", 1)[0].rstrip()
                values[name.strip()] = value
    return values.get("UNI_API_KEY") or values.get("API_SECRET", "")
