#!/usr/bin/env python3
"""Estimate the camera move between two frames of a shot (numpy + Pillow only).

usage: camera_motion.py first.png last.png

Searches zoom factors and, for each, the best translation by phase correlation on downscaled grayscale frames,
then keeps the zoom/shift with the highest normalised cross-correlation. Prints JSON:
  {"zoom": 1.18, "shift_x": -0.03, "shift_y": 0.02, "score": 0.91, "camera": "push-in ×1.18, pan left 3%"}
zoom > 1: the last frame shows a smaller, magnified part of the first (push-in / zoom in); < 1: pull-out.
shift_x / shift_y: where the matched region's centre sits relative to frame centre, as a fraction of width/height
(content moving left = camera panning right). A low score means the picture changed too much to match (a morph,
a cut, or heavy character motion) — check the strip by eye.
"""
import json
import sys

import numpy as np
from PIL import Image

W, H = 192, 108


def load(path):
    return np.asarray(Image.open(path).convert("L").resize((W, H), Image.BILINEAR), dtype=np.float64)


def crop_zoom(img_path, zoom):
    """Centre crop of 1/zoom of the frame, resized back to W×H (what a push-in by `zoom` would show)."""
    im = Image.open(img_path).convert("L")
    w, h = im.size
    cw, ch = w / zoom, h / zoom
    box = ((w - cw) / 2, (h - ch) / 2, (w + cw) / 2, (h + ch) / 2)
    return np.asarray(im.crop(box).resize((W, H), Image.BILINEAR), dtype=np.float64)


def phase_shift(a, b):
    """Integer (dy, dx) such that b ≈ a shifted by (dy, dx)."""
    win = np.outer(np.hanning(H), np.hanning(W))
    fa, fb = np.fft.fft2((a - a.mean()) * win), np.fft.fft2((b - b.mean()) * win)
    r = fb * np.conj(fa)
    r /= np.abs(r) + 1e-9
    corr = np.fft.ifft2(r).real
    dy, dx = np.unravel_index(np.argmax(corr), corr.shape)
    if dy > H // 2:
        dy -= H
    if dx > W // 2:
        dx -= W
    return int(dy), int(dx)


def ncc(a, b, dy, dx):
    """Normalised cross-correlation of the overlap of a shifted by (dy, dx) with b."""
    ys, yd = (slice(0, H - dy), slice(dy, H)) if dy >= 0 else (slice(-dy, H), slice(0, H + dy))
    xs, xd = (slice(0, W - dx), slice(dx, W)) if dx >= 0 else (slice(-dx, W), slice(0, W + dx))
    pa, pb = a[ys, xs], b[yd, xd]
    if pa.size < (H * W) // 4:
        return -1.0
    pa, pb = pa - pa.mean(), pb - pb.mean()
    return float((pa * pb).sum() / (np.sqrt((pa ** 2).sum() * (pb ** 2).sum()) + 1e-9))


def describe(zoom, sx, sy):
    parts = []
    if zoom > 1.03:
        parts.append(f"push-in ×{zoom:.2f}")
    elif zoom < 0.97:
        parts.append(f"pull-out ×{zoom:.2f}")
    # The region the camera ends on sits at (sx, sy) in the first frame: right of centre = the camera panned right.
    if abs(sx) >= 0.02:
        parts.append(f"pan {'right' if sx > 0 else 'left'} {abs(sx) * 100:.0f}%")
    if abs(sy) >= 0.02:
        parts.append(f"tilt/pedestal {'down' if sy > 0 else 'up'} {abs(sy) * 100:.0f}%")
    return ", ".join(parts) or "static (no measurable camera move)"


def main(first, last):
    b = load(last)
    a_full = load(first)
    best = None
    for zoom in np.round(np.arange(0.55, 1.901, 0.01), 2):
        if zoom >= 1:
            a = crop_zoom(first, zoom)  # the first frame magnified: compare with the last frame
            ref, cand = a, b
        else:
            ref, cand = a_full, crop_zoom(last, 1 / zoom)  # the last frame magnified back: compare with the first
        dy, dx = phase_shift(ref, cand)
        score = ncc(ref, cand, dy, dx)
        if best is None or score > best[0]:
            best = (score, float(zoom), dy, dx)
    score, zoom, dy, dx = best
    # Shift of content between ref and cand -> where the end framing sits in the first frame (fractions of the frame).
    scale = zoom if zoom >= 1 else 1.0
    sx, sy = -dx / W / scale, -dy / H / scale
    print(json.dumps({"zoom": round(zoom, 3), "shift_x": round(sx, 3), "shift_y": round(sy, 3),
                      "score": round(score, 3), "camera": describe(zoom, sx, sy)}))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
