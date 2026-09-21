"""Generate small original placeholder impact sounds for the prototype."""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
random.seed(18)
Path('audio').mkdir(exist_ok=True)


def write(name, seconds, sample):
    frames = bytearray()
    for n in range(int(RATE * seconds)):
        t = n / RATE
        value = max(-1.0, min(1.0, sample(t, seconds)))
        frames += struct.pack('<h', int(value * 32767))
    with wave.open(str(Path('audio') / name), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)


def hit(t, duration):
    envelope = math.exp(-t * 31)
    tone = math.sin(2 * math.pi * (420 * t - 530 * t * t))
    noise = random.uniform(-1, 1)
    return envelope * (0.48 * tone + 0.34 * noise)


def heavy(t, duration):
    envelope = math.exp(-t * 17)
    low = math.sin(2 * math.pi * (120 * t - 115 * t * t))
    crack = random.uniform(-1, 1) * math.exp(-t * 55)
    return 0.75 * envelope * low + 0.32 * crack


def swing(t, duration):
    envelope = math.sin(math.pi * t / duration) ** 2
    hiss = random.uniform(-1, 1)
    tone = math.sin(2 * math.pi * (190 * t + 390 * t * t))
    return envelope * (0.2 * hiss + 0.16 * tone)


write('hit.wav', 0.13, hit)
write('heavy_hit.wav', 0.24, heavy)
write('swing.wav', 0.18, swing)
