#!/usr/bin/env python3
"""Bake all offline speech with Fish Audio S2 Pro, locally on Apple Silicon.

Every role keeps one voice across all its lines by cloning a fixed reference
(data/voices/<role>.wav). The references are voices S2 invented itself, not
recordings of a real person: `--design` samples candidates, keeps those whose
pitch fits the role and writes them; `--bake` then speaks every phrase of
data/instructor_lines.json and data/bystander_lines.json in both
languages into assets/audio/tts_<lang>/<key>.wav and rewrites the manifest.

Runs inside the fish-speech checkout's environment (not the app's):
  ~/Projects/fish-speech/.venv/bin/python tools/generate_voices_fish.py --design
  ~/Projects/fish-speech/.venv/bin/python tools/generate_voices_fish.py --bake
Weights: `hf download fishaudio/s2-pro --local-dir checkpoints/s2-pro` in that
checkout. Fish Audio Research License: research and non-commercial use only.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
VOICES = ROOT / "data/voices"
AUDIO = ROOT / "assets/audio"
PHRASES = json.loads((ROOT / "data/instructor_lines.json").read_text(encoding="utf-8"))
for _key, _line in json.loads((ROOT / "data/bystander_lines.json").read_text(encoding="utf-8")).items():
    if not _key.startswith("_"):
        for _language in PHRASES:
            PHRASES[_language][_key] = _line[_language]

# Who speaks the fixed phrases that are not in data/bystander_lines.json.
LEGACY_SPEAKERS = {"calm": "anna", "help": "anna", "aed": "anna", "thanks": "anna"}
ROLES = {
    # role: (pitch range in Hz, style tag for the reference, reference sentence)
    "anna": ((165, 270), "[worried]", "Ich weiß nicht, was ich machen soll. Er ist einfach umgefallen, bitte helfen Sie uns doch."),
    # Deep on purpose: around 140 Hz S2's men were heard as female in the video review.
    "marek": ((80, 125), "[deep male voice, calm]", "Ich bin hier und helfe Ihnen. Sagen Sie mir einfach, was ich tun soll, dann mache ich das sofort."),
    # The AED speaks with the instructor's reference (data/voices/aed.* are copies).
    "aed": ((85, 270), "[calm, clear, steady]", "Wir beginnen jetzt die Übung. Prüfen Sie zuerst, ob die Person reagiert, und rufen Sie dann Hilfe."),
    "instructor": ((85, 270), "[calm, clear]", "Wir beginnen jetzt die Übung. Prüfen Sie zuerst, ob die Person reagiert, und rufen Sie dann Hilfe."),
}


def lines() -> dict:
    return json.loads((ROOT / "data/bystander_lines.json").read_text(encoding="utf-8"))


def speaker_of(key: str, table: dict) -> str:
    if key in table:
        return table[key]["speaker"]
    return LEGACY_SPEAKERS.get(key, "instructor")


def median_pitch(samples: np.ndarray, rate: int) -> float:
    """Crude autocorrelation F0 over voiced frames; enough to tell a man from a woman."""
    frame = int(rate * 0.04)
    pitches = []
    for start in range(0, len(samples) - frame, frame):
        seg = samples[start:start + frame].astype(np.float64)
        if np.mean(seg * seg) < 1e-4:
            continue
        seg -= seg.mean()
        corr = np.correlate(seg, seg, "full")[frame - 1:]
        lo, hi = int(rate / 400), int(rate / 70)
        lag = lo + int(np.argmax(corr[lo:hi]))
        if corr[lag] > 0.3 * corr[0]:
            pitches.append(rate / lag)
    return float(np.median(pitches)) if pitches else 0.0


class Voice:
    def __init__(self, fish: Path, device: str):
        os.chdir(fish)
        sys.path.insert(0, str(fish))
        from tools.server.model_manager import ModelManager  # fish-speech's own tools package
        from fish_speech.utils.schema import ServeReferenceAudio, ServeTTSRequest
        self._request, self._reference = ServeTTSRequest, ServeReferenceAudio
        self._engine = ModelManager(mode="tts", device=device, half=False, compile=False,
            llama_checkpoint_path="checkpoints/s2-pro", decoder_checkpoint_path="checkpoints/s2-pro/codec.pth",
            decoder_config_name="modded_dac_vq").tts_inference_engine

    def speak(self, text: str, reference: Path | None = None, seed: int = 7) -> tuple[int, np.ndarray]:
        refs = []
        if reference is not None:
            refs = [self._reference(audio=reference.read_bytes(), text=reference.with_suffix(".txt").read_text(encoding="utf-8"))]
        request = self._request(text=text, references=refs, seed=seed, max_new_tokens=1024, chunk_length=300,
            top_p=0.8, temperature=0.7, repetition_penalty=1.1, format="wav", use_memory_cache="on")
        for result in self._engine.inference(request):
            if result.code == "error":
                raise RuntimeError(result.error)
            if result.code == "final":
                rate, audio = result.audio
                return rate, np.asarray(audio, dtype=np.float32).reshape(-1)
        raise RuntimeError("no audio")


def write_wav(path: Path, rate: int, audio: np.ndarray) -> bytes:
    peak = float(np.max(np.abs(audio))) or 1.0
    pcm = (np.clip(audio / max(peak, 1e-6) * 0.89, -1, 1) * 32767).astype("<i2")
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(pcm.tobytes())
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(buffer.getvalue())
    return buffer.getvalue()


def design(voice: Voice, candidates: int, roles: list[str]) -> None:
    """Invent a voice per role; keep the first one whose pitch fits, save all to audition."""
    audition = ROOT / "build/voice_candidates"
    for role, ((low, high), tag, sentence) in ROLES.items():
        if roles and role not in roles:
            continue
        chosen = None
        for seed in range(1, candidates + 1):
            rate, audio = voice.speak(f"{tag} {sentence}", seed=seed * 101)
            pitch = median_pitch(audio, rate)
            write_wav(audition / f"{role}_{seed}_{int(pitch)}hz.wav", rate, audio)
            print(f"NARET_VOICE {role} seed={seed} pitch={pitch:.0f} Hz", flush=True)
            if chosen is None and low <= pitch <= high:
                chosen = (seed, rate, audio)
        if chosen is None:
            raise SystemExit(f"No candidate for {role} in {low}-{high} Hz; rerun with more --candidates")
        seed, rate, audio = chosen
        write_wav(VOICES / f"{role}.wav", rate, audio)
        (VOICES / f"{role}.txt").write_text(sentence, encoding="utf-8")
        print(f"NARET_VOICE_CHOSEN {role} seed={seed}", flush=True)


def bake(voice: Voice, only: set[str]) -> None:
    table = lines()
    manifest_path = AUDIO / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {"clips": []}
    kept = [c for c in manifest.get("clips", []) if only and c["key"] not in only]
    clips = []
    for language, phrases in PHRASES.items():
        for key, text in phrases.items():
            if only and key not in only:
                continue
            role = speaker_of(key, table)
            style = table.get(key, {}).get("style", ROLES[role][1])
            rate, audio = voice.speak(f"{style} {text}", reference=VOICES / f"{role}.wav")
            relative = f"tts_{language}/{key}.wav"
            data = write_wav(AUDIO / relative, rate, audio)
            clips.append({"key": key, "language": language, "speaker": role, "text": text, "file": relative,
                "duration_s": round(len(audio) / rate, 3), "sha256": hashlib.sha256(data).hexdigest()})
            print(f"NARET_CLIP {language}/{key} {role} {len(audio) / rate:.1f}s", flush=True)
    manifest = {"generator": "fish-audio-s2-pro (local, Fish Audio Research License)", "languages": ["de", "pl"],
        "voices": {role: f"data/voices/{role}.wav" for role in ROLES}, "clips": kept + clips}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"NARET_BAKED {len(clips)} clips", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fish", type=Path, default=Path.home() / "Projects/fish-speech")
    parser.add_argument("--device", default="mps")
    parser.add_argument("--design", action="store_true")
    parser.add_argument("--bake", action="store_true")
    parser.add_argument("--candidates", type=int, default=4)
    parser.add_argument("--only", nargs="*", default=[], help="phrase keys to re-bake")
    parser.add_argument("--roles", nargs="*", default=[], help="with --design: only these roles; with --bake: only their lines")
    args = parser.parse_args()
    if not (args.design or args.bake):
        parser.error("choose --design and/or --bake")
    voice = Voice(args.fish.expanduser(), args.device)
    if args.design:
        design(voice, args.candidates, args.roles)
    if args.bake:
        only = set(args.only)
        if args.roles:
            table = lines()
            only |= {key for phrases in PHRASES.values() for key in phrases if speaker_of(key, table) in args.roles}
        bake(voice, only)


if __name__ == "__main__":
    main()
