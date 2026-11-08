#!/usr/bin/env python3
"""Prepare character portraits for an animation: crop faces from accepted sheets into a reference collage,
then split an edited portrait sheet into named transparent images. Styling is chosen in the image-edit prompt;
the tool does not impose a genre, costume, icon frame or character proportions.

  .venv/bin/python -I tools/python/face_collage.py build <spec.json> <out.png> [--preview faces.jpg]
  .venv/bin/python -I tools/python/face_collage.py cut <edited.png> <spec.json> <out_dir> [--size 256]

spec.json:
  {"cols": 4, "rows": 2, "cell": [460, 520], "gap": 40, "margin": 60, "background": "#d8d8d8", "aspect": 1.7778,
   "faces": [{"name": "pilot", "sheet": "output/char-pilot-v1/01_ref_base.png", "box": [cx, cy, w], "scale": 4}, ...]}
  box is the face's centre and width in the sheet's pixels divided by `scale` (measure on a downscaled copy and give
  the copy's factor); the crop is w wide with the configured cell aspect ratio. Cells are filled row by row.

`cut` does not trust the model to keep the exact pixel grid: it finds the icons by projection (anything that differs
from the background colour), expects one per named face in reading order, and saves each one square (centred, padded with
transparency), at --size. If the count is off, it stops; --grid-fallback explicitly enables a measured content-grid fallback for review.
Needs Pillow and numpy only. Prints a JSON summary.
"""
import argparse
import json
import os
import sys
import re

import numpy as np
from PIL import Image


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def read_spec(path):
    spec = json.load(open(path))
    faces = spec["faces"]
    names = [f["name"] for f in faces]
    if not names or len(names) != len(set(names)) or any(not re.fullmatch(r"[A-Za-z0-9_-]+", n) for n in names):
        raise SystemExit("face names must be unique plain identifiers")
    if min(spec["cols"], spec["rows"], *spec["cell"]) <= 0 or len(faces) > spec["cols"] * spec["rows"]:
        raise SystemExit("invalid collage dimensions or too many faces")
    return spec


def layout(spec):
    cw, ch = spec["cell"]
    g, m, cols, rows = spec.get("gap", 40), spec.get("margin", 60), spec["cols"], spec["rows"]
    W, H = 2 * m + cols * cw + (cols - 1) * g, 2 * m + rows * ch + (rows - 1) * g
    # Pad to the edit model's output shape (16:9 by default), grid centred, so it doesn't re-lay the cells to fit.
    ar = spec.get("aspect", 16 / 9)
    ox = oy = 0
    if W / H < ar:
        ox = (round(H * ar) - W) // 2; W = round(H * ar)
    else:
        oy = (round(W / ar) - H) // 2; H = round(W / ar)
    cells = [(ox + m + c * (cw + g), oy + m + r * (ch + g), cw, ch) for r in range(rows) for c in range(cols)]
    return W, H, cells


def cmd_build(a):
    spec = read_spec(a.spec)
    W, H, cells = layout(spec)
    bg = hex_rgb(spec.get("background", "#d8d8d8"))
    out = Image.new("RGB", (W, H), bg)
    for face, (x, y, w, h) in zip(spec["faces"], cells):
        im = Image.open(face["sheet"]).convert("RGB")
        s = face.get("scale", 1)
        cx, cy, fw = [v * s for v in face["box"]]
        fh = fw * h / w
        crop = im.crop((round(cx - fw / 2), round(cy - fh / 2), round(cx + fw / 2), round(cy + fh / 2)))
        out.paste(crop.resize((w, h), Image.LANCZOS), (x, y))
    out.save(a.out)
    if a.preview:
        out.resize((W // 2, H // 2)).save(a.preview)
    print(json.dumps({"collage": a.out, "size": [W, H], "cells": len(spec["faces"])}))


def runs(profile, thresh, min_len):
    on = profile >= thresh
    spans, start = [], None
    for i, v in enumerate(list(on) + [False]):
        if v and start is None:
            start = i
        elif not v and start is not None:
            if i - start >= min_len:
                spans.append((start, i))
            start = None
    return spans


def cmd_cut(a):
    spec = read_spec(a.spec)
    im = Image.open(a.edited).convert("RGBA")
    arr = np.asarray(im).astype(np.int16)
    # The background: the median of the image's border pixels.
    border = np.concatenate([arr[:6].reshape(-1, 4), arr[-6:].reshape(-1, 4), arr[:, :6].reshape(-1, 4), arr[:, -6:].reshape(-1, 4)])
    bg = np.median(border[:, :3], axis=0)
    diff = np.abs(arr[..., :3] - bg).sum(axis=2)
    mask = (diff > a.tol) & (arr[..., 3] > 24)
    cols, rows, n = spec["cols"], spec["rows"], len(spec["faces"])
    H, W = mask.shape
    boxes = []
    for y0, y1 in runs(mask.sum(axis=1), max(4, W * 0.02), H // (rows * 4)):
        band = mask[y0:y1]
        for x0, x1 in runs(band.sum(axis=0), max(4, (y1 - y0) * 0.02), W // (cols * 4)):
            ys = np.where(band[:, x0:x1].any(axis=1))[0]
            boxes.append((x0, y0 + ys[0], x1 - x0, ys[-1] - ys[0] + 1))
    how = "found"
    if len(boxes) != n:
        if not a.grid_fallback:
            raise SystemExit(f"found {len(boxes)} icons, expected {n}; inspect the sheet, or explicitly enable grid fallback")
        if not mask.any():
            raise SystemExit("edited sheet contains no detectable icons")
        # Plates that nearly touch defeat the projection: split the content's bounding box evenly instead (the model
        # spaces the grid evenly even when it moves it), then trim each cell to what is in it.
        found = len(boxes)
        ys, xs = np.where(mask.any(axis=1))[0], np.where(mask.any(axis=0))[0]
        X0, X1, Y0, Y1 = xs[0], xs[-1] + 1, ys[0], ys[-1] + 1
        cw, ch = (X1 - X0) / cols, (Y1 - Y0) / rows
        boxes = []
        for i in range(n):
            x0, y0 = round(X0 + (i % cols) * cw), round(Y0 + (i // cols) * ch)
            x1, y1 = round(x0 + cw), round(y0 + ch)
            sub = mask[y0:y1, x0:x1]
            yy, xx = np.where(sub.any(axis=1))[0], np.where(sub.any(axis=0))[0]
            if not len(xx) or not len(yy):
                raise SystemExit("grid fallback found an empty cell; inspect the edited sheet")
            boxes.append((x0 + xx[0], y0 + yy[0], xx[-1] - xx[0] + 1, yy[-1] - yy[0] + 1))
        how = f"even split of the content box (projection found {found}, expected {n})"
    os.makedirs(a.out, exist_ok=True)
    res = {}
    for face, (x, y, w, h) in zip(spec["faces"], boxes):
        tile = im.crop((x, y, x + w, y + h))
        # Background-coloured pixels round the icon go transparent, so a round or chamfered plate keeps its shape.
        t = np.asarray(tile).copy()
        d = np.abs(t[..., :3].astype(np.int16) - bg).sum(axis=2)
        t[..., 3] = np.where(d > a.tol, t[..., 3], 0)
        tile = Image.fromarray(t, "RGBA")
        s = max(w, h)
        sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        sq.paste(tile, ((s - w) // 2, (s - h) // 2))
        sq.resize((a.size, a.size), Image.LANCZOS).save(os.path.join(a.out, f"{face['name']}.png"))
        res[face["name"]] = [int(x), int(y), int(w), int(h)]
    print(json.dumps({"icons": res, "how": how, "background": [int(v) for v in bg]}))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build"); b.add_argument("spec"); b.add_argument("out"); b.add_argument("--preview")
    c = sub.add_parser("cut"); c.add_argument("edited"); c.add_argument("spec"); c.add_argument("out")
    c.add_argument("--size", type=int, default=256); c.add_argument("--tol", type=int, default=60)
    c.add_argument("--grid-fallback", action="store_true")
    a = p.parse_args()
    spec = read_spec(a.spec)
    sources = [a.spec] + ([f["sheet"] for f in spec["faces"]] if a.cmd == "build" else [a.edited])
    outputs = [a.out] + ([a.preview] if a.preview else []) if a.cmd == "build" else [os.path.join(a.out, f["name"] + ".png") for f in spec["faces"]]
    if any(os.path.realpath(o) == os.path.realpath(i) for o in outputs for i in sources):
        p.error("outputs must not overwrite source files")
    if a.cmd == "cut" and a.size <= 0:
        p.error("size must be positive")
    for o in outputs:
        os.makedirs(os.path.dirname(os.path.abspath(o)), exist_ok=True)
    {"build": cmd_build, "cut": cmd_cut}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
