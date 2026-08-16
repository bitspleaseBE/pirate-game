#!/usr/bin/env python3
"""Synthesise the placeholder music stems and sea ambience.

These are stand-ins, exactly like the sound effects next door — docs/ASSETS.md
§14 lists the eight real tracks that eventually replace them. The point of
having them now is that the layering is a *gameplay* system, not decoration:
music that thickens as a fight starts tells the player something is happening
before they have finished parsing the screen, and that behaviour cannot be
designed, tuned or regression-tested against silence.

    python3 tools/audio/make_placeholder_music.py

Writes 16-bit mono 22.05 kHz WAVs to assets/audio/music/.

## Why the three stems are one piece of music

docs/ASSETS.md §14: "Author calm / tense / combat as stems in the same key and
tempo so they crossfade without a musical seam." That is the whole trick, and it
constrains this file more than anything else here:

  * every stem is the **same length to the sample**, so they stay in lockstep for
    as long as the game runs rather than drifting apart over a voyage;
  * they are the same key (D minor) and tempo (120 bpm), so any combination of
    them is the same piece of music;
  * they are **additive** — `tense` is what you add to `calm`, not a different
    arrangement of it — so the director only has to move three volumes and never
    has to decide when it is safe to switch tracks.

Crossfading whole tracks would need a musically safe moment to switch, which
means either waiting for one (the music reacts late, which is worse than no
music) or cutting on the beat (a seam every time a skiff appears).

## Deliberate duplication

The DSP helpers here overlap with make_placeholder_sfx.py. They are not shared,
for two reasons: this file runs at half the sample rate, and its primitives are
musical (notes, chords, a drum kit) where that file's are impulsive (cracks,
splashes). Factoring the overlap out would mean touching a script whose output is
committed and whose determinism is the reason it can be re-run safely.

Pure Python stdlib, no numpy: run it anywhere, commit the output, no build step.
"""

from __future__ import annotations

import math
import pathlib
import random
import struct
import wave

# Music does not need the SFX rate. Halving it halves the bytes in the repo for
# something no player will ever A/B against the real thing, and a shanty pad has
# nothing above 11 kHz to lose in the first place.
RATE = 22050
BPM = 120.0
BEAT = 60.0 / BPM
BAR = BEAT * 4.0
BARS = 4
LOOP_SECONDS = BAR * BARS

OUT_DIR = pathlib.Path(__file__).resolve().parents[2] / "assets" / "audio" / "music"

Signal = list[float]

# D minor. The progression is i – VI – III – VII, one bar each: the four chords
# every sea shanty ever written is made of, which is the correct amount of
# invention for a placeholder.
A4 = 440.0


def note(semitones_from_a4: float) -> float:
    return A4 * (2.0 ** (semitones_from_a4 / 12.0))


# Root, and the triad above it, per bar.
CHORDS: list[tuple[float, tuple[float, float, float]]] = [
    (note(-19), (note(-7), note(-4), note(0))),    # Dm  : D  F  A
    (note(-23), (note(-11), note(-7), note(-4))),  # Bb  : Bb D  F
    (note(-16), (note(-4), note(0), note(3))),     # F   : F  A  C
    (note(-21), (note(-9), note(-5), note(-2))),   # C   : C  E  G
]

# A plain four-bar tune over the top, as (bar, beat, semitone, beats-long).
MELODY: list[tuple[int, float, float, float]] = [
    (0, 0.0, note(0), 1.5), (0, 1.5, note(2), 0.5), (0, 2.0, note(3), 2.0),
    (1, 0.0, note(2), 1.0), (1, 1.0, note(0), 1.0), (1, 2.0, note(-2), 2.0),
    (2, 0.0, note(0), 1.5), (2, 1.5, note(3), 0.5), (2, 2.0, note(5), 2.0),
    (3, 0.0, note(3), 1.0), (3, 1.0, note(2), 1.0), (3, 2.0, note(0), 2.0),
]


def silence(seconds: float) -> Signal:
    return [0.0] * int(RATE * seconds)


def add_into(target: Signal, source: Signal, at_seconds: float, gain: float = 1.0) -> None:
    """Mixes `source` into `target` in place, wrapping past the end of the loop.

    Wrapping rather than clipping is what makes the loop seam work: a note or a
    cymbal that starts near the end of the last bar has its tail land at the top
    of the first, which is exactly where it will be heard when the file repeats.
    """
    start = int(at_seconds * RATE)
    n = len(target)
    if n == 0:
        return
    for i, sample in enumerate(source):
        target[(start + i) % n] += sample * gain


def adsr(n: int, attack: float, decay: float, sustain: float, release: float) -> Signal:
    """Envelope over `n` samples, with the four segments given in seconds."""
    out: Signal = []
    a = max(1, int(attack * RATE))
    d = max(1, int(decay * RATE))
    r = max(1, int(release * RATE))
    s = max(0, n - a - d - r)
    for i in range(n):
        if i < a:
            out.append(i / a)
        elif i < a + d:
            out.append(1.0 - (1.0 - sustain) * ((i - a) / d))
        elif i < a + d + s:
            out.append(sustain)
        else:
            k = (i - a - d - s) / r
            out.append(max(0.0, sustain * (1.0 - k)))
    return out


def reed(freq: float, seconds: float, detune: float = 0.006) -> Signal:
    """An accordion-ish tone: a few detuned saws, softened.

    Odd and even harmonics both present and a slow beat between the detuned
    copies, which is most of what makes a free-reed instrument sound like one
    rather than like a synthesiser.
    """
    n = int(seconds * RATE)
    out: Signal = [0.0] * n
    for k, ratio in enumerate((1.0, 1.0 + detune, 1.0 - detune)):
        phase = 0.0
        step = freq * ratio / RATE
        for i in range(n):
            phase = (phase + step) % 1.0
            # Naive saw, then a soft fold — cheap, and the lowpass below tames it.
            saw = 2.0 * phase - 1.0
            out[i] += saw * (0.34 if k == 0 else 0.22)
    return lowpass(out, 1800.0)


def whistle(freq: float, seconds: float) -> Signal:
    """A near-sine lead with a little breath, for the melody."""
    n = int(seconds * RATE)
    out: Signal = []
    phase = 0.0
    rng = random.Random(int(freq * 100.0))
    for i in range(n):
        # Gentle vibrato, arriving rather than present from the first sample.
        t = i / RATE
        depth = min(1.0, t * 3.0) * 0.004
        phase += (freq * (1.0 + math.sin(2.0 * math.pi * 5.2 * t) * depth)) / RATE
        value = math.sin(2.0 * math.pi * phase)
        value += 0.12 * math.sin(4.0 * math.pi * phase)
        out.append(value + rng.uniform(-0.02, 0.02))
    return lowpass(out, 3200.0)


def lowpass(sig: Signal, cutoff_hz: float) -> Signal:
    a = math.exp(-2.0 * math.pi * cutoff_hz / RATE)
    out: Signal = []
    y = 0.0
    for x in sig:
        y = (1.0 - a) * x + a * y
        out.append(y)
    return out


def highpass(sig: Signal, cutoff_hz: float) -> Signal:
    return [x - y for x, y in zip(sig, lowpass(sig, cutoff_hz))]


def kick(rng: random.Random) -> Signal:
    n = int(0.22 * RATE)
    out: Signal = []
    phase = 0.0
    for i in range(n):
        t = i / n
        freq = 120.0 * (0.28 ** t) + 42.0
        phase += 2.0 * math.pi * freq / RATE
        out.append(math.sin(phase) * ((1.0 - t) ** 2.2))
    return out


def snare(rng: random.Random) -> Signal:
    n = int(0.16 * RATE)
    body = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    body = highpass(body, 900.0)
    env = [(1.0 - i / n) ** 2.6 for i in range(n)]
    return [b * e * 0.7 for b, e in zip(body, env)]


def stab(freqs: tuple[float, ...], seconds: float) -> Signal:
    """A short brass-ish chord hit."""
    n = int(seconds * RATE)
    out: Signal = [0.0] * n
    for freq in freqs:
        phase = 0.0
        for i in range(n):
            phase += 2.0 * math.pi * freq / RATE
            # Squarish, for bite.
            out[i] += math.sin(phase) + 0.32 * math.sin(3.0 * phase)
    env = adsr(n, 0.006, 0.05, 0.55, seconds * 0.6)
    return [v * e / max(1, len(freqs)) for v, e in zip(out, env)]


def seam_fade(sig: Signal, ms: float = 4.0) -> Signal:
    """Ramps the first and last few milliseconds so the loop wraps continuously.

    Without it the last sample and the first sample are unrelated values, and the
    step between them is a click — once every eight seconds, forever, at a level
    low enough to be dismissed as "something in the mix" and never diagnosed.
    Four milliseconds is short enough that even the kick drum sitting on the
    downbeat keeps its attack.
    """
    n = len(sig)
    edge = max(1, int(ms * 0.001 * RATE))
    if n < edge * 2:
        return sig
    out = list(sig)
    for i in range(edge):
        k = i / edge
        out[i] *= k
        out[n - 1 - i] *= k
    return out


def normalise(sig: Signal, peak: float = 0.8) -> Signal:
    high = max((abs(x) for x in sig), default=0.0)
    if high < 1e-6:
        return sig
    scale = peak / high
    return [x * scale for x in sig]


def soft_clip(sig: Signal) -> Signal:
    return [math.tanh(x * 1.15) for x in sig]


def write_wav(name: str, sig: Signal) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{name}.wav"
    frames = bytearray()
    for x in sig:
        frames += struct.pack("<h", int(max(-1.0, min(1.0, x)) * 32767))
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(bytes(frames))
    print(f"  {path.name}  {len(sig) / RATE:.1f}s  {len(frames) // 1024} KiB")


# --- The three stems -------------------------------------------------------


def stem_calm() -> Signal:
    """Sustained reed chords and the tune. What you hear at sea with nobody about."""
    out = silence(LOOP_SECONDS)
    for bar, (root, triad) in enumerate(CHORDS):
        at = bar * BAR
        # The chord, held for the whole bar with a soft attack.
        for freq in triad:
            voice = reed(freq, BAR * 0.98)
            env = adsr(len(voice), 0.14, 0.25, 0.72, 0.30)
            add_into(out, [v * e for v, e in zip(voice, env)], at, 0.22)
        # Root an octave down, so the bed has a floor.
        low = reed(root, BAR * 0.98, detune=0.004)
        env = adsr(len(low), 0.18, 0.3, 0.8, 0.3)
        add_into(out, [v * e for v, e in zip(low, env)], at, 0.16)

    for bar, beat, freq, length in MELODY:
        voice = whistle(freq, BEAT * length * 0.95)
        env = adsr(len(voice), 0.03, 0.08, 0.7, BEAT * length * 0.4)
        add_into(out, [v * e for v, e in zip(voice, env)], bar * BAR + beat * BEAT, 0.20)

    return seam_fade(soft_clip(normalise(out, 0.55)))


def stem_tense() -> Signal:
    """A drone and a walking bass. Added on top of calm when something is out there."""
    out = silence(LOOP_SECONDS)

    # One held low D under the whole loop — the thing that makes a scene feel
    # like it is about to become a problem.
    drone = reed(note(-31), LOOP_SECONDS, detune=0.003)
    add_into(out, drone, 0.0, 0.20)

    for bar, (root, _triad) in enumerate(CHORDS):
        for eighth in range(8):
            at = bar * BAR + eighth * BEAT * 0.5
            # Alternate root and fifth, the way a bass line does.
            freq = root if eighth % 4 != 2 else root * 1.4983
            voice = reed(freq, BEAT * 0.42, detune=0.002)
            env = adsr(len(voice), 0.008, 0.06, 0.5, BEAT * 0.2)
            add_into(out, [v * e for v, e in zip(voice, env)], at, 0.26)

    return seam_fade(soft_clip(normalise(out, 0.5)))


def stem_combat() -> Signal:
    """Drums and brass. Added when the shooting starts."""
    out = silence(LOOP_SECONDS)
    rng = random.Random(20240816)

    for bar in range(BARS):
        for beat in range(4):
            at = bar * BAR + beat * BEAT
            if beat in (0, 2):
                add_into(out, kick(rng), at, 0.85)
            else:
                add_into(out, snare(rng), at, 0.5)
            # An off-beat kick in the last bar, so the loop pushes into itself
            # rather than sitting flat for four identical bars.
            if bar == BARS - 1 and beat == 3:
                add_into(out, kick(rng), at + BEAT * 0.5, 0.6)

    for bar, (_root, triad) in enumerate(CHORDS):
        add_into(out, stab(triad, BEAT * 0.8), bar * BAR, 0.30)
        add_into(out, stab(triad, BEAT * 0.5), bar * BAR + BEAT * 2.5, 0.20)

    return seam_fade(soft_clip(normalise(out, 0.72)))


# --- Ambience --------------------------------------------------------------


def sea_ambience() -> Signal:
    """Ten seconds of sea, under everything, forever.

    Not part of the music: it runs on its own bus at its own volume and never
    stops, because the one thing every frame of this game has in common is that
    it is happening on water. Deliberately a different length from the music
    loop, so the two do not line up into an audible four-second pattern.
    """
    seconds = 10.0
    n = int(seconds * RATE)
    rng = random.Random(1789)

    base = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    body = lowpass(base, 700.0)
    hiss = highpass(base, 2600.0)

    out: Signal = []
    for i in range(n):
        t = i / RATE
        # Two swells at incommensurable periods, so the wash never repeats
        # inside the loop even though the file does.
        swell = 0.55 + 0.45 * (
            0.6 * math.sin(2.0 * math.pi * t / 6.3)
            + 0.4 * math.sin(2.0 * math.pi * t / 4.1 + 1.7)
        )
        out.append(body[i] * swell + hiss[i] * 0.16 * swell)

    # Fade the seam. A ten-second noise loop with a hard edge clicks once every
    # ten seconds forever, which is the most irritating possible bug to diagnose.
    edge = int(0.35 * RATE)
    for i in range(edge):
        k = i / edge
        out[i] *= k
        out[n - 1 - i] *= k

    return soft_clip(normalise(out, 0.42))


TRACKS = {
    "mus_layer_calm": stem_calm,
    "mus_layer_tense": stem_tense,
    "mus_layer_combat": stem_combat,
    "amb_sea": sea_ambience,
}


def main() -> None:
    print(f"Writing music to {OUT_DIR}")
    print(f"  {BPM:.0f} bpm, {BARS} bars, {LOOP_SECONDS:.1f}s loop, {RATE} Hz")
    lengths: dict[str, int] = {}
    for name, build in TRACKS.items():
        signal = build()
        lengths[name] = len(signal)
        write_wav(name, signal)

    # The stems are only stems if they are the same length to the sample. Drift
    # here would not error, it would slowly turn a chord into a cluster over the
    # course of a voyage, which is exactly the kind of fault nobody attributes to
    # a generator script.
    stems = [n for n in TRACKS if n.startswith("mus_layer_")]
    if len({lengths[n] for n in stems}) != 1:
        raise SystemExit(
            "stem lengths differ, so they will drift out of sync: %s"
            % {n: lengths[n] for n in stems}
        )
    print(f"OK — {len(stems)} stems at {lengths[stems[0]]} samples each")


if __name__ == "__main__":
    main()
