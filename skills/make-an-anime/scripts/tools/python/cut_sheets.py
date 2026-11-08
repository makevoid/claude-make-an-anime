#!/usr/bin/env python3
"""Cut generated game-art sheets into transparent PNGs a p5 overlay loads, and measure a HUD frame's empty screens.

Run with the project's venv and -I (the sheets are generated files, treat them as data):

  .venv/bin/python -I tools/python/cut_sheets.py sprites <sheet.png> <out_dir> --names a,b,c,... [--key alpha|magenta|black]
      Sprites laid out in rows with clear gaps (a unit sheet). Rows are found from the alpha (or keyed) coverage along y,
      then sprites inside each row along x, so the order is row by row, left to right. Each sprite is trimmed with a
      small margin and saved as <out_dir>/<name>.png. Specks smaller than --min-px pixels per row/column are ignored.

  .venv/bin/python -I tools/python/cut_sheets.py grid <sheet.png> <out_dir> --names a,b,... [--key black] [--inset 0]
      Icons on a flat background in a grid: the same row/column search, each tile saved square, at --size px (128).

  .venv/bin/python -I tools/python/cut_sheets.py frame <console.png> <out.png> <slots.json> [--key alpha|magenta]
      A HUD frame with a keyed-out top: writes the transparent frame (its flat-black screens made transparent too,
      so whatever p5 draws under the frame shows through them) and slots.json, the screens' rectangles in the frame's
      own pixels, largest first, as {"w", "h", "slots": [[x, y, w, h], ...]}.

  .venv/bin/python -I tools/python/cut_sheets.py fit <image.png> <out.png> --width W [--crop x,y,w,h]
      An opaque picture (terrain, portrait): optional crop, then resize to W wide.

Prints a JSON summary on stdout. Needs Pillow and numpy only.
"""
import argparse
import json
import os
import sys
import re
from collections import deque

import numpy as np
from PIL import Image


def load_rgba(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.int16)


def coverage(a, key):
    """Boolean mask of 'something here' for a sheet, by its keying mode."""
    if key == "alpha":
        return a[..., 3] > 24
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    if key == "magenta":
        return (a[..., 3] > 24) & ~((r > 170) & (b > 170) & (g < 110))
    if key == "black":
        return (a[..., 3] > 24) & ((r + g + b) > 60)
    raise SystemExit(f"unknown key {key}")


def key_alpha(a, key):
    """RGBA uint8 with the background made transparent (soft edge for magenta)."""
    out = a.copy()
    if key == "magenta":
        r, g, b = a[..., 0], a[..., 1], a[..., 2]
        dist = np.minimum(r, b) - g                      # high on magenta
        alpha = np.clip((140 - dist) * 255 / 90, 0, 255)
        out[..., 3] = np.minimum(a[..., 3], alpha)
        spill = (out[..., 3] < 255) & (out[..., 3] > 0)  # pull the magenta spill out of the soft edge
        avg = (r + b) // 2
        out[..., 0] = np.where(spill, np.minimum(r, g + 20), r)
        out[..., 2] = np.where(spill, np.minimum(b, g + 20), b)
        del avg
    elif key == "black":
        lum = a[..., :3].max(axis=2)
        out[..., 3] = np.minimum(a[..., 3], np.clip((lum - 8) * 255 / 40, 0, 255))
    return np.clip(out, 0, 255).astype(np.uint8)


def runs(profile, min_px, min_len, gap=6):
    """[(start, end)) spans where profile >= min_px, merging gaps shorter than `gap`, dropping spans shorter than min_len."""
    on = profile >= min_px
    spans, start, last = [], None, None
    for i, v in enumerate(on):
        if v:
            if start is None:
                start = i
            elif last is not None and i - last > gap:
                spans.append((start, last + 1))
                start = i
            last = i
    if start is not None:
        spans.append((start, last + 1))
    return [(s, e) for s, e in spans if e - s >= min_len]


def find_boxes(mask, min_px, min_len, gap):
    boxes = []
    for y0, y1 in runs(mask.sum(axis=1), min_px, min_len, gap):
        band = mask[y0:y1]
        for x0, x1 in runs(band.sum(axis=0), min_px, min_len, gap):
            sub = band[:, x0:x1]
            ys = np.where(sub.sum(axis=1) >= 1)[0]
            boxes.append((x0, y0 + ys[0], x1 - x0, ys[-1] - ys[0] + 1))
    return boxes


def cmd_sprites(args):
    a = load_rgba(args.sheet)
    mask = coverage(a, args.key)
    boxes = find_boxes(mask, args.min_px, args.min_len, args.gap)
    names = args.names.split(",")
    if len(boxes) != len(names):
        raise SystemExit(f"found {len(boxes)} sprites, expected {len(names)}: {boxes}")
    rgba = key_alpha(a, args.key)
    os.makedirs(args.out, exist_ok=True)
    out = {}
    m = args.margin
    for name, (x, y, w, h) in zip(names, boxes):
        x0, y0 = max(0, x - m), max(0, y - m)
        x1, y1 = min(a.shape[1], x + w + m), min(a.shape[0], y + h + m)
        crop = rgba[y0:y1, x0:x1].copy()
        if args.key != "alpha":
            crop[..., 3] = np.where(coverage(a[y0:y1, x0:x1], args.key), crop[..., 3], 0)
        Image.fromarray(crop, "RGBA").save(os.path.join(args.out, f"{name}.png"))
        out[name] = {"box": [int(x0), int(y0), int(x1 - x0), int(y1 - y0)]}
    print(json.dumps({"sprites": out}))


def cmd_grid(args):
    a = load_rgba(args.sheet)
    mask = coverage(a, args.key)
    boxes = find_boxes(mask, args.min_px, args.min_len, args.gap)
    names = args.names.split(",")
    if len(boxes) != len(names):
        raise SystemExit(f"found {len(boxes)} tiles, expected {len(names)}: {boxes}")
    os.makedirs(args.out, exist_ok=True)
    out = {}
    for name, (x, y, w, h) in zip(names, boxes):
        s = max(w, h)
        cx, cy = x + w // 2, y + h // 2
        i = args.inset
        if 2 * i >= s:
            raise SystemExit("inset removes the entire tile")
        tile = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").crop((cx - s // 2 + i, cy - s // 2 + i, cx + s // 2 - i, cy + s // 2 - i))
        tile.resize((args.size, args.size), Image.LANCZOS).save(os.path.join(args.out, f"{name}.png"))
        out[name] = {"box": [int(x), int(y), int(w), int(h)]}
    print(json.dumps({"tiles": out}))


def label(mask):
    """4-connected components of a small boolean mask -> list of (x, y, w, h, area)."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    comps = []
    for y in range(h):
        row = mask[y]
        for x in np.where(row & ~seen[y])[0]:
            if seen[y, x]:
                continue
            q = deque([(y, x)])
            seen[y, x] = True
            x0 = x1 = x
            y0 = y1 = y
            n = 0
            while q:
                cy, cx = q.popleft()
                n += 1
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
            comps.append((x0, y0, x1 - x0 + 1, y1 - y0 + 1, n))
    return comps


def cmd_frame(args):
    a = load_rgba(args.console)
    rgba = key_alpha(a, args.key) if args.key != "alpha" else np.clip(a, 0, 255).astype(np.uint8)
    solid = rgba[..., 3] > 200
    dark = solid & (a[..., :3].max(axis=2) < args.dark)
    f = args.scale
    small = dark[::f, ::f]
    comps = [c for c in label(small) if c[4] >= args.min_area and c[4] >= 0.8 * c[2] * c[3]]  # filled, box-like
    comps.sort(key=lambda c: -c[4])
    slots = [[int(x * f), int(y * f), int(w * f), int(h * f)] for x, y, w, h, _ in comps]
    # Clear the screens so the layer under the frame shows through them.
    hole = np.zeros(dark.shape, dtype=bool)
    for x, y, w, h in slots:
        hole[y:y + h, x:x + w] = True
    rgba = rgba.copy()
    rgba[..., 3] = np.where(hole & dark, 0, rgba[..., 3])
    Image.fromarray(rgba, "RGBA").save(args.out)
    top = int(np.where(solid.any(axis=1))[0][0]) if solid.any() else 0
    json.dump({"w": int(a.shape[1]), "h": int(a.shape[0]), "top": top, "slots": slots}, open(args.slots, "w"), indent=1)
    print(json.dumps({"frame": args.out, "slots": len(slots), "top": top}))


def cmd_fit(args):
    im = Image.open(args.image).convert("RGB")
    if args.crop:
        x, y, w, h = [int(v) for v in args.crop.split(",")]
        im = im.crop((x, y, x + w, y + h))
    W = args.width
    im = im.resize((W, round(im.height * W / im.width)), Image.LANCZOS)
    im.save(args.out)
    print(json.dumps({"fit": args.out, "size": im.size}))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("sprites", "grid"):
        s = sub.add_parser(name)
        s.add_argument("sheet"); s.add_argument("out")
        s.add_argument("--names", required=True)
        s.add_argument("--key", default="alpha" if name == "sprites" else "black")
        s.add_argument("--min-px", type=int, default=6)
        s.add_argument("--min-len", type=int, default=40)
        s.add_argument("--gap", type=int, default=24)
        s.add_argument("--margin", type=int, default=6)
        s.add_argument("--size", type=int, default=128)
        s.add_argument("--inset", type=int, default=0)
    s = sub.add_parser("frame")
    s.add_argument("console"); s.add_argument("out"); s.add_argument("slots")
    s.add_argument("--key", default="alpha")
    s.add_argument("--dark", type=int, default=22)
    s.add_argument("--scale", type=int, default=4)
    s.add_argument("--min-area", type=int, default=300)
    s = sub.add_parser("fit")
    s.add_argument("image"); s.add_argument("out")
    s.add_argument("--width", type=int, required=True)
    s.add_argument("--crop")
    args = p.parse_args()
    if args.cmd in ("sprites", "grid"):
        names = args.names.split(",")
        if len(names) != len(set(names)) or any(not re.fullmatch(r"[A-Za-z0-9_-]+", n) for n in names):
            p.error("names must be unique plain identifiers")
        if min(args.min_px, args.min_len, args.size) <= 0 or min(args.gap, args.margin, args.inset) < 0:
            p.error("invalid dimensions or detection thresholds")
        outputs = [os.path.join(args.out, f"{n}.png") for n in names]
        source = args.sheet
    else:
        source = args.console if args.cmd == "frame" else args.image
        outputs = [args.out] + ([args.slots] if args.cmd == "frame" else [])
        if args.cmd == "frame" and min(args.scale, args.min_area) <= 0:
            p.error("scale and min-area must be positive")
        if args.cmd == "fit" and args.width <= 0:
            p.error("width must be positive")
    if any(os.path.realpath(o) == os.path.realpath(source) for o in outputs):
        p.error("outputs must not overwrite the source sheet")
    for o in outputs:
        os.makedirs(os.path.dirname(os.path.abspath(o)), exist_ok=True)
    {"sprites": cmd_sprites, "grid": cmd_grid, "frame": cmd_frame, "fit": cmd_fit}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
