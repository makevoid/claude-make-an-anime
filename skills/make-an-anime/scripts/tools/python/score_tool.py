"""Small local edits of a shaped score wav, numpy only, no Fal calls.
Usage: .venv/bin/python3 -I tools/python/score_tool.py <cmd> IN OUT args...
  insert IN OUT T L [CF]       rewind: at T jump back L seconds (inserts x[T-L:T] again), crossfade CF (default 0.06)
  remove IN OUT T L [CF]       cut L seconds starting at T, crossfade CF
  freeze IN OUT T A B END DB0 DB1   from T add a spectral freeze of x[A:B] whose level goes DB0 -> DB1 (dBFS RMS) by
                               END-0.4, faded out by END; the file is padded/trimmed to END seconds
  length IN OUT SECONDS [FADE]  pad with silence / trim to SECONDS, optional fade-out FADE at the end
  crossfade IN OUT T L         a hard change of music at T becomes a crossfade over L seconds: the last chord before T is
                               held (spectral freeze) and fades out while the new section fades in; the length is unchanged
  soften IN OUT T L in|out     an abrupt start or stop of the music at T gets a fade of L seconds, after T for in, before T for out
"""
import sys, wave
import numpy as np


def load(p):
    w = wave.open(p)
    sr, ch = w.getframerate(), w.getnchannels()
    assert w.getsampwidth() == 2
    x = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, ch).astype(np.float64) / 32768
    return x, sr


def save(p, x, sr):
    y = np.clip(np.round(x * 32768), -32768, 32767).astype(np.int16)
    w = wave.open(p, "wb")
    w.setnchannels(x.shape[1]); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(y.tobytes()); w.close()


def xfade(a, b, n):
    """a then b, overlapping the last n samples of a with the first n of b (equal power)."""
    t = np.linspace(0, 1, n)[:, None]
    mid = a[-n:] * np.cos(t * np.pi / 2) + b[:n] * np.sin(t * np.pi / 2)
    return np.concatenate([a[:-n], mid, b[n:]])


def insert(x, sr, T, L, cf):
    T, S, h = int(round(T * sr)), int(round((T - L) * sr)), int(cf * sr / 2)
    return xfade(x[:T + h], x[S - h:], 2 * h)


def remove(x, sr, T, L, cf):
    T, E, h = int(round(T * sr)), int(round((T + L) * sr)), int(cf * sr / 2)
    return xfade(x[:T + h], x[E - h:], 2 * h)


def hold(seg, n, sr, seed=39):
    """n samples sustaining seg's sound: its averaged spectrum resynthesised with new phases, at seg's level."""
    n_fft, hop = 4096, 1024
    win = np.hanning(n_fft)
    rng = np.random.default_rng(seed)
    out = np.zeros((n + n_fft, seg.shape[1]))
    for c in range(seg.shape[1]):
        frames = [np.abs(np.fft.rfft(seg[i:i + n_fft, c] * win)) for i in range(0, max(len(seg) - n_fft, 1), hop)]
        mag = np.mean(frames, axis=0)
        for i in range(0, n, hop):
            phase = rng.uniform(0, 2 * np.pi, len(mag))
            out[i:i + n_fft, c] += np.fft.irfft(mag * np.exp(1j * phase), n_fft) * win
    out = out[:n]
    rms = lambda a: np.sqrt(np.mean(a ** 2)) + 1e-9
    return out * (rms(seg) / rms(out))


def crossfade(x, sr, T, L):
    t, n = int(T * sr), int(L * sr)
    x = x.copy()
    held = hold(x[max(t - int(0.6 * sr), 0):t], n, sr)
    ramp = np.linspace(0, 1, n)[:, None]
    x[t:t + n] = x[t:t + n] * np.sin(ramp * np.pi / 2) + held * np.cos(ramp * np.pi / 2)
    return x


def soften(x, sr, T, L, kind):
    x = x.copy()
    t, n = int(T * sr), int(L * sr)
    ramp = np.linspace(0, 1, n)[:, None]
    if kind == "in":
        x[t:t + n] *= ramp
    else:
        x[t - n:t] *= ramp[::-1]
    return x


def freeze(x, sr, T, A, B, END, db0, db1):
    n_fft, hop = 4096, 1024
    win = np.hanning(n_fft)
    seg = x[int(A * sr):int(B * sr)]
    total = int(round(END * sr))
    if len(x) < total:
        x = np.concatenate([x, np.zeros((total - len(x), x.shape[1]))])
    x = x[:total].copy()
    start = int(T * sr) - int(0.1 * sr)
    n = total - start
    rng = np.random.default_rng(38)
    out = np.zeros((n + n_fft, x.shape[1]))
    for c in range(x.shape[1]):
        frames = [np.abs(np.fft.rfft(seg[i:i + n_fft, c] * win)) for i in range(0, len(seg) - n_fft, hop // 2)]
        mag = np.mean(frames, axis=0)
        for i in range(0, n, hop):
            ph = np.exp(2j * np.pi * rng.random(len(mag)))
            out[i:i + n_fft, c] += np.fft.irfft(mag * ph) * win
    out = out[:n]
    rms = np.sqrt((out[int(0.3 * sr):] ** 2).mean()) + 1e-12
    t = np.arange(n) / sr
    dur = (total - start) / sr
    lvl = 10 ** ((db0 + (db1 - db0) * np.clip((t - 0.1) / max(0.1, dur - 0.5), 0, 1)) / 20)
    env = lvl / rms * np.clip(t / 0.3, 0, 1)                       # fade in over 0.3 s from T-0.1
    env *= np.clip((dur - t) / 0.4, 0, 1)                          # fade out by END
    x[start:] += out * env[:, None]
    return x


def length(x, sr, secs, fade):
    total = int(round(secs * sr))
    x = np.concatenate([x, np.zeros((max(0, total - len(x)), x.shape[1]))])[:total].copy()
    if fade:
        n = int(fade * sr)
        x[-n:] *= np.linspace(1, 0, n)[:, None]
    return x


if __name__ == "__main__":
    cmd, src, dst, *a = sys.argv[1:]
    x, sr = load(src)
    kind = a.pop() if cmd == "soften" else None
    a = [float(v) for v in a]
    if cmd == "insert": y = insert(x, sr, a[0], a[1], a[2] if len(a) > 2 else 0.06)
    elif cmd == "remove": y = remove(x, sr, a[0], a[1], a[2] if len(a) > 2 else 0.06)
    elif cmd == "freeze": y = freeze(x, sr, *a)
    elif cmd == "length": y = length(x, sr, a[0], a[1] if len(a) > 1 else 0)
    elif cmd == "crossfade": y = crossfade(x, sr, a[0], a[1])
    elif cmd == "soften": y = soften(x, sr, a[0], a[1], kind)
    else: raise SystemExit(__doc__)
    save(dst, y, sr)
    print(f"{cmd}: {len(x)/sr:.3f}s -> {len(y)/sr:.3f}s  peak {np.abs(y).max():.3f}")
