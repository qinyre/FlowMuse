"""Rebuild the original audio sketch: Python 3 + the existing NumPy install."""
from pathlib import Path
import hashlib
import json
import wave

import numpy as np

OUT = Path(__file__).resolve().parent
RATE = 48000
LOOP = 32.0
CROSSFADE = 0.3


def frequency(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def write_checked(name, signal, seconds, loop=False):
    signal = signal - signal.mean(axis=0)
    signal *= 0.45 / np.max(np.abs(signal))
    pcm = np.round(signal * 32767).astype('<i2')
    path = OUT / name
    with wave.open(str(path), 'wb') as wav:
        wav.setparams((2, 2, RATE, len(pcm), 'NONE', 'not compressed'))
        wav.writeframes(pcm.tobytes())
    with wave.open(str(path), 'rb') as wav:
        decoded = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2').reshape(-1, 2) / 32768.0
        assert wav.getnchannels() == 2 and wav.getframerate() == RATE
        assert wav.getnframes() == round(seconds * RATE)
    peak = float(np.max(np.abs(decoded)))
    seam = float(np.max(np.abs(decoded[-1] - decoded[0])))
    seam_prediction = ((decoded[1] - decoded[0]) + (decoded[-1] - decoded[-2])) / 2
    seam_error = float(np.max(np.abs(decoded[0] - decoded[-1] - seam_prediction)))
    assert np.isfinite(decoded).all() and 0.3 < peak < 0.46
    assert seam_error < 0.0003, f'{name}: boundary discontinuity exceeds the local waveform slope'
    if not loop:
        assert np.max(np.abs(decoded[[0, -1]])) < 0.0001
    return dict(file=name, duration_seconds=seconds, sample_rate=RATE, channels=2,
                peak_dbfs=round(20 * np.log10(peak), 2),
                rms_dbfs=round(20 * np.log10(np.sqrt(np.mean(decoded ** 2))), 2),
                seam_delta=round(seam, 8), seam_slope_error=round(seam_error, 8), loop=loop,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def main():
    # ponytail: four repeated chords are a listening sketch, replace this track when arranging a final score.
    t = np.arange(round((LOOP + CROSSFADE) * RATE)) / RATE
    bed = np.zeros((len(t), 2))
    chords = [(48, 55, 59, 62, 64), (45, 52, 55, 59, 60),
              (41, 48, 52, 55, 57), (43, 50, 55, 57, 59)]
    for chord_index, chord in enumerate(chords):
        age = (t - chord_index * 8) % LOOP
        attack = np.sin(np.minimum(age / 1.8, 1) * np.pi / 2) ** 2
        release = np.cos(np.clip((age - 7.0) / 3.0, 0, 1) * np.pi / 2) ** 2
        envelope = attack * release * (age < 10)
        for voice, midi in enumerate(chord):
            f = frequency(midi)
            pan = (voice - 2) * 0.12
            gains = np.sqrt([(1 - pan) / 2, (1 + pan) / 2])
            for side, gain in enumerate(gains):
                phase = 2 * np.pi * (f + (side * 2 - 1) * 0.09) * age
                tone = np.sin(phase) + 0.13 * np.sin(phase * 2) + 0.035 * np.sin(phase * 3)
                bed[:, side] += tone * envelope * gain * (0.10 if voice else 0.14)
    # Sparse soft upper notes, with exponential release and no percussive samples.
    for index, (start, midi) in enumerate([(1.2, 76), (5.4, 74), (9.5, 71), (13.3, 72),
                                         (17.2, 69), (21.6, 67), (25.2, 71), (29.0, 74)]):
        age = (t - start) % LOOP
        envelope = np.minimum(age / 0.07, 1) ** 2 * np.exp(-age / 1.4) * (age < 7)
        tone = np.sin(2 * np.pi * frequency(midi) * age)
        pan = -0.17 if index % 2 else 0.17
        bed += (tone * envelope * 0.055)[:, None] * np.sqrt([(1 - pan) / 2, (1 + pan) / 2])
    n, overlap = round(LOOP * RATE), round(CROSSFADE * RATE)
    weight = (0.5 - 0.5 * np.cos(np.linspace(0, np.pi, overlap)))[:, None]
    bed[:overlap] = bed[n:n + overlap] * (1 - weight) + bed[:overlap] * weight
    report = [write_checked('emerald-ambient-demo.wav', bed[:n], LOOP, loop=True)]

    t = np.arange(round(1.4 * RATE)) / RATE
    envelope = (1 - np.exp(-t / 0.018)) ** 2 * np.exp(-t / 0.28)
    envelope *= np.sin(np.minimum((1.4 - t) / 0.25, 1) * np.pi / 2) ** 2
    ping = (np.sin(2 * np.pi * frequency(76) * t) + 0.22 * np.sin(2 * np.pi * frequency(83) * t)) * envelope
    ping = np.column_stack((ping, np.interp(t - 0.004, t, ping, left=0)))
    ping[:480] *= np.linspace(0, 1, 480)[:, None]
    ping[-480:] *= np.linspace(1, 0, 480)[:, None]
    report.append(write_checked('soft-reveal-demo.wav', ping, 1.4))
    (OUT / 'audio-check.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
