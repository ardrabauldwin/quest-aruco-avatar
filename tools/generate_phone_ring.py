"""Phone sound for Anna's 112 call: three keypad tones (1, 1, 2) and two ringback bursts.

Synthesised, no recording. European ringback is a 425 Hz tone, 1 s on and 4 s off;
the second pause is shortened so the whole clip stays under seven seconds.

    python tools/generate_phone_ring.py
writes assets/audio/sfx/phone_ring.wav (mono, 22050 Hz, 16 bit).
"""
import math
import pathlib
import struct
import wave

RATE = 22050
DTMF = {"1": (697, 1209), "2": (697, 1336)}


def tone(freqs, seconds, gain, fade=0.01):
    out = []
    n = int(RATE * seconds)
    ramp = max(1, int(RATE * fade))
    for i in range(n):
        env = min(1.0, i / ramp, (n - 1 - i) / ramp)
        value = sum(math.sin(2 * math.pi * f * i / RATE) for f in freqs) / len(freqs)
        out.append(gain * env * value)
    return out


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def build():
    samples = []
    samples += silence(0.6)
    for key in "112":
        samples += tone(DTMF[key], 0.16, 0.35)
        samples += silence(0.12)
    samples += silence(0.7)
    samples += tone([425], 1.0, 0.4, 0.02)
    samples += silence(2.0)
    samples += tone([425], 1.0, 0.4, 0.02)
    samples += silence(0.3)
    return samples


def main():
    path = pathlib.Path(__file__).resolve().parents[1] / "assets" / "audio" / "sfx" / "phone_ring.wav"
    path.parent.mkdir(parents=True, exist_ok=True)
    samples = build()
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    print("written", path, "%.2f s" % (len(samples) / RATE))


if __name__ == "__main__":
    main()
