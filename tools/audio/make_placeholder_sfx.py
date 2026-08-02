#!/usr/bin/env python3
"""Synthesise placeholder sound effects for Pirates: Treasure Hunt.

These are stand-ins, not final audio — docs/ASSETS.md §13 lists the ~45 real
cues (with variants) that eventually replace them. The point of having them now
is that a cannon you cannot hear is a cannon you cannot time, and the whole
broadside mechanic is about timing.

Pure Python stdlib, no numpy: run it anywhere, commit the output, and the game
has sound with no build step.

    python3 tools/audio/make_placeholder_sfx.py

Writes 16-bit mono 44.1 kHz WAVs to assets/audio/sfx/.
"""

from __future__ import annotations

import math
import pathlib
import random
import struct
import wave
import zlib

RATE = 44100
OUT_DIR = pathlib.Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"

Signal = list[float]


def silence(seconds: float) -> Signal:
    return [0.0] * int(RATE * seconds)


def noise(seconds: float, rng: random.Random) -> Signal:
    return [rng.uniform(-1.0, 1.0) for _ in range(int(RATE * seconds))]


def sine(seconds: float, freq_start: float, freq_end: float | None = None) -> Signal:
    n = int(RATE * seconds)
    freq_end = freq_start if freq_end is None else freq_end
    out: Signal = []
    phase = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        # Exponential sweep reads as a more natural pitch glide than a linear one.
        freq = freq_start * ((freq_end / freq_start) ** t) if freq_start > 0 else 0.0
        phase += 2.0 * math.pi * freq / RATE
        out.append(math.sin(phase))
    return out


def one_pole_lowpass(sig: Signal, cutoff_hz: float) -> Signal:
    a = math.exp(-2.0 * math.pi * cutoff_hz / RATE)
    out: Signal = []
    y = 0.0
    for x in sig:
        y = (1.0 - a) * x + a * y
        out.append(y)
    return out


def one_pole_highpass(sig: Signal, cutoff_hz: float) -> Signal:
    low = one_pole_lowpass(sig, cutoff_hz)
    return [x - y for x, y in zip(sig, low)]


def envelope(sig: Signal, attack: float, decay: float, curve: float = 2.5) -> Signal:
    n = len(sig)
    a = max(1, int(RATE * attack))
    out: Signal = []
    for i, x in enumerate(sig):
        if i < a:
            gain = i / a
        else:
            t = (i - a) / max(1.0, RATE * decay)
            gain = math.exp(-curve * t)
        out.append(x * gain)
    return out


def mix(*signals: Signal) -> Signal:
    length = max(len(s) for s in signals)
    out = [0.0] * length
    for s in signals:
        for i, x in enumerate(s):
            out[i] += x
    return out


def gain(sig: Signal, amount: float) -> Signal:
    return [x * amount for x in sig]


def normalise(sig: Signal, peak: float = 0.85) -> Signal:
    high = max((abs(x) for x in sig), default=0.0)
    if high < 1e-6:
        return sig
    scale = peak / high
    return [x * scale for x in sig]


def soft_clip(sig: Signal) -> Signal:
    # tanh keeps the transients loud without the crunch of hard clipping.
    return [math.tanh(x * 1.4) for x in sig]


def write_wav(name: str, sig: Signal) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{name}.wav"
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, x)) * 32767)) for x in sig
    )
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(frames)
    print(f"  {path.name:24s} {len(sig) / RATE:.2f}s")


# --- Cues -------------------------------------------------------------------


def cannon_fire(rng: random.Random) -> Signal:
    """Crack, body, and a low thump — the three parts of a gun going off."""
    crack = envelope(one_pole_highpass(noise(0.06, rng), 2200.0), 0.0005, 0.02, 6.0)
    body = envelope(one_pole_lowpass(noise(0.55, rng), 700.0), 0.002, 0.13, 3.0)
    thump = envelope(sine(0.5, 105.0, 42.0), 0.003, 0.10, 3.5)
    tail = envelope(one_pole_lowpass(noise(0.9, rng), 260.0), 0.02, 0.35, 2.0)
    return soft_clip(
        normalise(mix(gain(crack, 0.75), gain(body, 1.0), gain(thump, 0.9), gain(tail, 0.3)))
    )


def impact_wood(rng: random.Random) -> Signal:
    """Splintering hit: a hard knock plus a scatter of debris."""
    knock = envelope(one_pole_lowpass(noise(0.18, rng), 1400.0), 0.0005, 0.045, 5.0)
    thud = envelope(sine(0.22, 190.0, 90.0), 0.001, 0.05, 5.0)
    splinter = envelope(one_pole_highpass(noise(0.3, rng), 3200.0), 0.001, 0.09, 3.0)
    return normalise(mix(gain(knock, 1.0), gain(thud, 0.7), gain(splinter, 0.45)))


def splash(rng: random.Random) -> Signal:
    """Bright spray settling into a low gulp."""
    spray = envelope(one_pole_highpass(noise(0.5, rng), 1500.0), 0.004, 0.14, 3.0)
    gulp = envelope(one_pole_lowpass(noise(0.45, rng), 480.0), 0.01, 0.12, 3.5)
    return normalise(mix(gain(spray, 0.9), gain(gulp, 0.7)), 0.7)


def explosion(rng: random.Random) -> Signal:
    blast = envelope(one_pole_lowpass(noise(1.1, rng), 900.0), 0.001, 0.30, 2.4)
    boom = envelope(sine(0.9, 130.0, 34.0), 0.002, 0.22, 2.6)
    debris = envelope(one_pole_highpass(noise(0.7, rng), 2600.0), 0.01, 0.20, 2.2)
    return soft_clip(normalise(mix(gain(blast, 1.0), gain(boom, 1.0), gain(debris, 0.35))))


def ship_sink(rng: random.Random) -> Signal:
    """Timber groan over a long gurgle."""
    groan = envelope(sine(1.6, 150.0, 48.0), 0.08, 0.75, 1.6)
    creak = envelope(one_pole_lowpass(noise(1.6, rng), 320.0), 0.1, 0.7, 1.5)
    bubbles = envelope(one_pole_lowpass(noise(1.8, rng), 900.0), 0.4, 0.6, 1.4)
    return normalise(mix(gain(groan, 0.8), gain(creak, 0.6), gain(bubbles, 0.4)), 0.75)


def coin_pickup(_rng: random.Random) -> Signal:
    a = envelope(sine(0.09, 1180.0), 0.001, 0.03, 5.0)
    b = envelope(sine(0.14, 1760.0), 0.001, 0.045, 5.0)
    return normalise(mix(a, silence(0.045) + b), 0.6)


def island_captured(_rng: random.Random) -> Signal:
    """Short rising fanfare — three notes of a major triad."""
    parts: Signal = []
    for i, freq in enumerate((392.0, 523.25, 659.25, 783.99)):
        note = envelope(mix(sine(0.42, freq), gain(sine(0.42, freq * 2.0), 0.3)), 0.006, 0.16, 3.0)
        parts = mix(parts or silence(0.0), silence(0.11 * i) + note)
    return normalise(parts, 0.7)


def ui_tap(_rng: random.Random) -> Signal:
    return normalise(envelope(sine(0.05, 900.0, 700.0), 0.001, 0.016, 6.0), 0.45)


def ui_confirm(_rng: random.Random) -> Signal:
    a = envelope(sine(0.07, 660.0), 0.001, 0.025, 6.0)
    b = envelope(sine(0.10, 990.0), 0.001, 0.035, 6.0)
    return normalise(mix(a, silence(0.05) + b), 0.5)


def ui_cancel(_rng: random.Random) -> Signal:
    a = envelope(sine(0.08, 520.0), 0.001, 0.03, 6.0)
    b = envelope(sine(0.12, 330.0), 0.001, 0.045, 6.0)
    return normalise(mix(a, silence(0.05) + b), 0.5)


CUES = {
    "cannon_fire": cannon_fire,
    "impact_wood": impact_wood,
    "splash": splash,
    "explosion": explosion,
    "ship_sink": ship_sink,
    "coin_pickup": coin_pickup,
    "island_captured": island_captured,
    "ui_tap": ui_tap,
    "ui_confirm": ui_confirm,
    "ui_cancel": ui_cancel,
}


def main() -> None:
    print(f"Writing placeholder SFX to {OUT_DIR}")
    for name, build in CUES.items():
        # crc32, not hash(): Python salts string hashing per process, so hash()
        # would give a different waveform on every run and churn git on rebuild.
        write_wav(name, build(random.Random(zlib.crc32(name.encode()))))
    print(f"{len(CUES)} cues written.")


if __name__ == "__main__":
    main()
