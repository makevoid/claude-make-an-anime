#!/usr/bin/env python3
"""How fast the near ground passes in a shot, ignoring the characters (numpy + ffmpeg only).

usage: world_motion.py VIDEO

A running character needs the world to pass behind them. A figure pumping its limbs over a ground that hardly moves
reads as a green-screen treadmill, whether or not it was keyed. Only the near ground tells them apart: in a real tracking
shot the sky, the sun and a far bridge barely move, so a measure over the whole frame scores a good run below a bad one.

The lower part of each sampled pair of frames is split into tiles, and each tile gets its own horizontal and vertical
shift by phase correlation. The median tile is the ground, because a runner's legs cover a minority of the tiles.

Prints JSON:
  {"world_speed": 0.62, "seconds": 3.04, "pairs": 36, "tiles": 8.0}
world_speed: median speed of the near ground, in frame widths per second.
tiles: average number of textured tiles used per pair (few tiles mean a flat picture and a weak estimate).
"""
import json
import subprocess
import sys

import numpy as np

W, H = 480, 270
BAND_TOP = 0.55  # the near ground: the bottom 45% of the frame
COLS, ROWS = 4, 2  # wide tiles, because fast ground can move far between two frames
STEP = 2  # frames between the two frames of a pair
MIN_TEXTURE = 3.0  # grey-level standard deviation below which a tile is too flat to give a shift


def fps_of(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=r_frame_rate",
         "-of", "csv=p=0", path], capture_output=True, check=True, text=True).stdout.strip().split(",")[0]
    num, den = out.split("/")
    return float(num) / float(den)


def frames(path):
    proc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", path, "-vf", f"scale={W}:{H}", "-f", "rawvideo", "-pix_fmt", "gray", "-"],
        stdout=subprocess.PIPE)
    size = W * H
    while (buf := proc.stdout.read(size)) and len(buf) == size:
        yield np.frombuffer(buf, dtype=np.uint8).reshape(H, W).astype(np.float64)
    proc.wait()


def tile_shift(a, b):
    """Pixels between two tiles by phase correlation."""
    h, w = a.shape
    win = np.outer(np.hanning(h), np.hanning(w))
    fa, fb = np.fft.fft2((a - a.mean()) * win), np.fft.fft2((b - b.mean()) * win)
    r = fb * np.conj(fa)
    r /= np.abs(r) + 1e-9
    corr = np.fft.ifft2(r).real
    dy, dx = np.unravel_index(np.argmax(corr), corr.shape)
    dy = dy - h if dy > h // 2 else dy
    dx = dx - w if dx > w // 2 else dx
    return float(np.hypot(dy, dx))


def pair_motion(a, b):
    """Median shift of the textured ground tiles, in pixels, and how many tiles were usable."""
    top = int(H * BAND_TOP)
    th, tw = (H - top) // ROWS, W // COLS
    shifts = []
    for row in range(ROWS):
        for col in range(COLS):
            y, x = top + row * th, col * tw
            ta = a[y:y + th, x:x + tw]
            if ta.std() >= MIN_TEXTURE:
                shifts.append(tile_shift(ta, b[y:y + th, x:x + tw]))
    return (float(np.median(shifts)), len(shifts)) if shifts else (0.0, 0)


def measure(path):
    fps = fps_of(path)
    clip = list(frames(path))
    if len(clip) <= STEP:
        raise SystemExit(f"{path}: too short to measure ({len(clip)} frames)")
    pairs = [pair_motion(clip[i], clip[i + STEP]) for i in range(0, len(clip) - STEP, STEP)]
    per_pair = float(np.median([p[0] for p in pairs]))
    return {
        "world_speed": round(per_pair / W / (STEP / fps), 4),
        "seconds": round(len(clip) / fps, 3),
        "pairs": len(pairs),
        "tiles": round(float(np.mean([p[1] for p in pairs])), 1),
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: world_motion.py VIDEO")
    print(json.dumps(measure(sys.argv[1])))
