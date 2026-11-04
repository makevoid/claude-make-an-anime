"""Find abrupt audio in a film: every join between scenes, and hard changes inside a scene's score.

usage: audio_seams.py film.mp4 rows.json       rows: [[run, seconds], ...] in film order; prints JSON.

seams:  for each scene join, the level just before and just after it. A track that is still sounding in its last 30 ms was
        cut, not ended; one that is loud in its first 30 ms starts without a fade (fine for a hit, wrong for a bed).
joints: for each scene's score file, the biggest changes between the 0.4 s either side of a point, spectrum and level, with
        how far the point is from a composition-plan chunk boundary. A chunk boundary with sound on both sides and a big
        change is a hard change of music, the kind score_tool.py crossfade fixes.
"""
import glob
import json
import os
import re
import subprocess
import sys

import numpy as np

SR = 22050


def pcm(path):
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True).stdout, dtype=np.float32)


def db(x):
    return float(20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-6)) if len(x) else -120.0


def spectrum(x):
    s = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    s = np.add.reduceat(s, np.unique(np.geomspace(1, len(s) - 1, 40).astype(int)))
    return s / (np.linalg.norm(s) + 1e-9)


def seams(a, rows):
    out, t = [], 0.0
    for i, (run, seconds) in enumerate(rows):
        if i:
            c = int(t * SR)
            n = int(0.03 * SR)
            out.append({"join": f"{rows[i - 1][0]}>{run}", "at": round(t, 2),
                        "last_30ms": round(db(a[c - n:c]), 1), "first_30ms": round(db(a[c:c + n]), 1),
                        "cut": bool(db(a[c - n:c]) > -45), "hard_start": bool(db(a[c:c + n]) > -30)})
        t += seconds
    return out


def score_file(run):
    configs = glob.glob("config/generations/*.rb") + ["config/generations.rb"]
    text = next((open(p).read() for p in configs if os.path.exists(p) and f'"{run}" =>' in open(p).read()), "")
    m = re.search(r'music_from: "([^"]+)"', text)
    if m and os.path.exists(m.group(1)):
        return m.group(1)
    takes = glob.glob(f"output/{run}/03_music_*s.wav")
    return max(takes, key=os.path.getmtime) if takes else None


def chunk_times(run):
    path = f"prompts/{run}/03_score.json"
    if not os.path.exists(path):
        return []
    return list(np.cumsum([c["duration_ms"] / 1000 for c in json.load(open(path)).get("chunks", [])]))


def joints(run):
    path = score_file(run)
    if not path:
        return []
    a, w, step, found = pcm(path), int(0.4 * SR), int(0.05 * SR), []
    for c in range(w, len(a) - w, step):
        before, after = a[c - w:c], a[c:c + w]
        la, lb = db(before), db(after)
        if max(la, lb) < -40:
            continue
        found.append((float(1 - np.dot(spectrum(before), spectrum(after))), c / SR, la, lb))
    found.sort(reverse=True)
    picked, chunks = [], chunk_times(run)
    for jump, at, la, lb in found:
        if jump < 0.5:
            break
        if all(abs(at - p["at"]) > 1.0 for p in picked):
            near = min((abs(at - c) for c in chunks), default=None)
            picked.append({"run": run, "at": round(at, 2), "jump": round(jump, 2), "before_db": round(la, 1), "after_db": round(lb, 1),
                           "kind": "stop" if lb < -60 else "start" if la < -60 else "change",
                           "chunk_boundary": bool(near is not None and near < 0.5), "file": path})
        if len(picked) == 3:
            break
    return picked


def main():
    film, rows = sys.argv[1], json.load(open(sys.argv[2]))
    report = {"seams": seams(pcm(film), rows), "joints": [j for run, _ in rows for j in joints(run)]}
    report["joints"].sort(key=lambda j: -j["jump"])
    print(json.dumps(report))


if __name__ == "__main__":
    main()
