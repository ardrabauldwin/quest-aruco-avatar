"""Summarize local tuning evidence without assuming text labels are ground truth.

Usage: python tools/audit_speech_tuning.py --wav path.wav [--wav another.wav]
No audio upload, model calls, transcript text output, or parameter modifications.
"""
import argparse
from array import array
import json
from pathlib import Path
import statistics
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]


def wav_summary(path):
    with wave.open(str(path), "rb") as wav:
        width, channels, rate = wav.getsampwidth(), wav.getnchannels(), wav.getframerate()
        duration = wav.getnframes() / rate
        data = wav.readframes(wav.getnframes())
    if width != 2:
        return {"path": str(path), "duration_s": duration, "error": "requires_pcm16"}
    samples = array("h", data)
    if sys.byteorder != "little":
        samples.byteswap()
    block = max(1, int(rate * 0.02)) * channels
    levels = [(sum((sample / 32768) ** 2 for sample in samples[i:i + block]) /
               len(samples[i:i + block])) ** 0.5 for i in range(0, len(samples), block)]
    ordered = sorted(levels)
    return {"path": str(path), "duration_s": round(duration, 3), "channels": channels,
            "sample_rate": rate, "analysis_block_ms": 20,
            "median_rms": statistics.median(levels) if levels else 0,
            "p95_rms": ordered[min(len(ordered) - 1, int(len(ordered) * 0.95))] if ordered else 0,
            "fraction_above_0_02": sum(v > 0.02 for v in levels) / max(1, len(levels)),
            "interpretation": "Signal summary only; speech/noise and word boundaries are not labelled."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wav", action="append", type=Path, default=[])
    parser.add_argument("--output", type=Path, default=ROOT / "build/speech-tuning-audit.json")
    args = parser.parse_args()
    candidates = ROOT / "integrations/finetuning/real_headset/candidates.jsonl"
    rows = [json.loads(line) for line in candidates.read_text(encoding="utf-8").splitlines() if line.strip()]
    reviewed = [row for row in rows if row.get("human_reviewed") and row.get("spoken_ground_truth")]
    report = {"headset_candidates": len(rows), "reviewed_with_spoken_ground_truth": len(reviewed),
        "languages": sorted({row.get("language", "unknown") for row in rows}),
        "wavs": [wav_summary(path) for path in args.wav],
        "conclusion": "Insufficient reviewed audio/negative examples to optimize ASR/VAD or fuzzy thresholds.",
        "recommendation": "Collect labelled speech/noise and permitted/rejected reports; tune on development sessions and evaluate separate held-out sessions. Do not report a numeric optimum from unreviewed/synthetic text."}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()
