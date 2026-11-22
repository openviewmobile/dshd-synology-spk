#!/usr/bin/env python3
"""Generate a deterministic, royalty-free ambient bed for the DSHD promo."""
import math, struct, wave

SR = 44100
DUR = 50.0
N = int(SR * DUR)
left = [0.0] * N
right = [0.0] * N

def add(i, v, pan=0.0):
    if 0 <= i < N:
        l = math.sqrt((1.0 - pan) * 0.5)
        r = math.sqrt((1.0 + pan) * 0.5)
        left[i] += v * l
        right[i] += v * r

def smooth(x):
    return x * x * (3.0 - 2.0 * x)

# Am - F - C - G, four seconds each.
chords = [
    (220.00, 261.63, 329.63),
    (174.61, 220.00, 261.63),
    (261.63, 329.63, 392.00),
    (196.00, 246.94, 293.66),
]
# pads
for ci, chord in enumerate(chords * 13):
    start = ci * 4.0
    if start >= DUR:
        break
    for ni, f in enumerate(chord):
        for k, amp in ((1, 0.055), (2, 0.018), (3, 0.006)):
            # slight detune between stereo channels
            for side, det in ((0, -0.12), (1, 0.12)):
                ff = f * k + det
                phase = ni * 0.7 + k * 0.3
                i0 = int(start * SR)
                i1 = min(N, int((start + 4.0) * SR))
                for i in range(i0, i1):
                    t = (i - i0) / SR
                    env = smooth(min(1.0, t / 0.9)) * smooth(min(1.0, (4.0 - t) / 1.1))
                    v = amp * env * math.sin(2 * math.pi * ff * (i / SR) + phase)
                    add(i, v, -0.25 if side == 0 else 0.25)

# sub bass pulse at chord roots
for ci in range(13):
    start = ci * 4.0
    if start >= DUR:
        break
    root = chords[ci % 4][0] * 0.5
    i0 = int(start * SR)
    i1 = min(N, int((start + 2.0) * SR))
    for i in range(i0, i1):
        t = (i - i0) / SR
        env = smooth(min(1.0, t / 0.08)) * math.exp(-1.7 * t)
        add(i, 0.16 * env * math.sin(2 * math.pi * root * (i / SR)))

# gentle heartbeat / kick every two seconds
for beat in range(0, int(DUR), 2):
    i0 = int(beat * SR)
    i1 = min(N, int((beat + 0.6) * SR))
    for i in range(i0, i1):
        t = (i - i0) / SR
        env = math.exp(-9.0 * t)
        add(i, 0.10 * env * math.sin(2 * math.pi * (52 - 12 * t) * t))

# transition risers / whooshes
for at in (7.4, 15.4, 25.4, 34.4, 42.4):
    i0 = int((at - 0.9) * SR)
    i1 = min(N, int((at + 0.45) * SR))
    for i in range(max(0, i0), i1):
        t = (i - i0) / SR
        env = math.exp(-2.2 * max(0.0, t - 1.0)) * smooth(min(1.0, t / 0.8))
        if t < 1.0:
            env = smooth(t)
        # deterministic pseudo-noise plus a rising tone
        n = math.sin(i * 12.9898 + 78.233) * 43758.5453
        n = (n - math.floor(n)) * 2.0 - 1.0
        sweep = 380 + 1100 * min(1.0, t)
        add(i, 0.025 * env * n + 0.018 * env * math.sin(2 * math.pi * sweep * t))

# global fade
fade = int(2.5 * SR)
for i in range(N):
    e = 1.0
    if i < fade:
        e = smooth(i / fade)
    if i > N - fade:
        e = min(e, smooth((N - i) / fade))
    left[i] *= e
    right[i] *= e

# normalize to -3 dBFS
peak = max(max(abs(x) for x in left), max(abs(x) for x in right)) or 1.0
gain = 0.70 / peak
with wave.open('assets/music.wav', 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    frames = bytearray()
    for l, r in zip(left, right):
        frames += struct.pack('<hh', int(max(-1, min(1, l * gain)) * 32767),
                              int(max(-1, min(1, r * gain)) * 32767))
    w.writeframes(frames)
print('wrote assets/music.wav', round(N / SR, 2), 'seconds')
