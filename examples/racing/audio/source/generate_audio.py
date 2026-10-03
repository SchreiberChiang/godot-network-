#!/usr/bin/env python3
"""Original deterministic synthesis, Python 3 + NumPy; no external audio inputs."""
from pathlib import Path
import numpy as np
import wave

SR = 48000
ROOT = Path(__file__).resolve().parents[1]
LOOPS = ['engine_idle_loop', 'engine_drive_loop', 'tire_skid_loop', 'nitro_loop']

def noise(n, low, high, seed):
    rng = np.random.default_rng(seed)
    f = np.fft.rfftfreq(n, 1 / SR)
    # Soft broad band, periodic inverse FFT, not a narrow whistling oscillator.
    weight = np.exp(-((f / high) ** 4)) * (1 - np.exp(-((f / low) ** 4)))
    spec = (rng.normal(size=len(f)) + 1j * rng.normal(size=len(f))) * weight
    spec[0] = spec[-1] = 0
    x = np.fft.irfft(spec, n=n)
    return x / np.std(x)

def write(name, x, peak):
    assert np.isfinite(x).all()
    x = x - x.mean()
    if name not in LOOPS:
        # Remove residual DC without leaving a hard onset/end discontinuity.
        edge = round(.003 * SR)
        fade = np.sin(np.linspace(0, np.pi/2, edge))**2
        x[:edge] *= fade
        x[-edge:] *= fade[::-1]
    x = x * (peak / np.max(np.abs(x)))
    q = np.rint(x * 32767).astype('<i2')
    path = ROOT / 'audio' / (name + '.wav')
    with wave.open(str(path), 'wb') as w:
        w.setparams((1, 2, SR, len(q), 'NONE', 'not compressed'))
        w.writeframes(q.tobytes())
    if name in LOOPS:
        with wave.open(str(ROOT / 'audition' / (name + '_3x.wav')), 'wb') as w:
            w.setparams((1, 2, SR, 3 * len(q), 'NONE', 'not compressed'))
            w.writeframes(np.tile(q, 3).tobytes())

def main():
    for d in ['audio', 'audition']:
        (ROOT / d).mkdir(exist_ok=True)
    n = SR * 2
    t = np.arange(n) / SR
    # Integer cycles over 2 s, including modulation, preserve the wrap boundary.
    idle = sum(a * np.sin(2*np.pi*f*t + 0.35*np.sin(2*np.pi*2*t))
               for a, f in [(1, 52), (.38, 104), (.16, 156), (.08, 208)])
    idle = idle * (1 + .10*np.sin(2*np.pi*4*t)) + .035*noise(n, 70, 600, 11)
    write('engine_idle_loop', idle, .40)
    drive = sum(a * np.sin(2*np.pi*f*t + .22*np.sin(2*np.pi*3*t))
                for a, f in [(1, 92), (.48, 184), (.23, 276), (.10, 368), (.04, 460)])
    drive = drive * (1 + .08*np.sin(2*np.pi*8*t)) + .07*noise(n, 100, 1100, 12)
    write('engine_drive_loop', drive, .48)
    skid = noise(n, 380, 2100, 13) * (1 + .13*np.sin(2*np.pi*5*t))
    skid += .08*np.sin(2*np.pi*165*t)
    write('tire_skid_loop', skid, .38)
    nitro = noise(n, 150, 1600, 14) * (1 + .07*np.sin(2*np.pi*3*t))
    nitro += .19*np.sin(2*np.pi*68*t) + .10*np.sin(2*np.pi*136*t)
    write('nitro_loop', nitro, .43)
    t = np.arange(round(.28 * SR)) / SR
    env = (1 - np.exp(-t/.003)) * np.exp(-t/.045)
    impact = env * (np.sin(2*np.pi*(120*t - 95*t*t)) + .35*noise(len(t), 100, 1900, 15))
    impact *= np.minimum(1, (t[-1] - t) / .025)
    write('impact_soft', impact, .54)
    t = np.arange(round(.18 * SR)) / SR
    env = np.sin(np.pi*np.minimum(t/.008, 1)/2)**2
    env *= np.sin(np.pi*np.minimum((t[-1]-t)/.025, 1)/2)**2
    beep = env * (np.sin(2*np.pi*740*t) + .09*np.sin(2*np.pi*1480*t))
    write('countdown_beep', beep, .35)

if __name__ == '__main__':
    main()
