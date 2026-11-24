#!/usr/bin/env python3
"""Writes the three timer tones to assets/sounds as small 16-bit mono WAV files.

Sine beeps made here, not downloaded: nothing to license. Run from apps/mobile:
  python3 tool/make_timer_tones.py
"""
import math
import struct
import wave

RATE = 22050


def tone(parts, name):
    """parts: [(frequency Hz, seconds)]. A short fade at each end avoids clicks."""
    frames = []
    for freq, secs in parts:
        n = int(RATE * secs)
        fade = int(RATE * 0.01)
        for i in range(n):
            env = min(1.0, i / fade, (n - i) / fade)
            frames.append(int(32767 * 0.6 * env * math.sin(2 * math.pi * freq * i / RATE)))
    with wave.open(f"assets/sounds/{name}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", f) for f in frames))


tone([(880, 0.15)], "timer_start")  # one short mid tone
tone([(1200, 0.06)], "timer_tick")  # a very short high tick
tone([(660, 0.25), (880, 0.25), (1100, 0.5)], "timer_end")  # a rising, longer tone
