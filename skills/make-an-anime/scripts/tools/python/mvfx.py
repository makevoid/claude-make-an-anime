#!/usr/bin/env python3
"""mvfx.py: the VFX finishing pass for machines without Swift and Core Image (Windows, Linux).

A port of tools/vfx (Swift) with the same command line, cue file and output, so lib/media/vfx.rb can run either:

  mvfx.py --in video.mp4 --cues cues.json --out out.mp4 [--lights dir] [--from N --to M]
  mvfx.py --in video.mp4 --cues cues.json --stills dir --only 120,503,1296 [--lights dir]

Frames come from ffmpeg as raw BGR and go back to ffmpeg (libx264 crf 16, the source's audio copied or cut to the range),
with the same accurate swscale rounding as the Swift tool. A frame no cue touches is passed through byte for byte, so an
empty cue list is a clean re-encode. The cue state per frame (envelopes, anchors, the SplitMix64 jitter) is a line-by-line
port of Effects.swift / Cues.swift; the filters are NumPy/OpenCV approximations of the Core Image ones, on the CPU.

  fx        shape  knobs (defaults)
  punch     hit    amt 0.06, radius 2 (zoom blur), x/y anchor 0.5/0.5
  zoom      ramp   amt 0.08, x/y
  shake     hit    amt 14 (px)
  whip      -      amt 0.12 (of width), radius 70, angle 0 (deg), pre
  mblur     hit    amt 30 (px), angle 0
  edgeblur  span   amt 10 (px), fade 6
  glow      hit    amt 1.0, radius 18
  flash     hit    amt 1.0, color #fffaf0
  dark      hit    amt 0.94, hold 2
  rgb       hit    amt 0.006
  glitch    span   amt 1.0, fade 1
  tv        span   amt 1.0, fade 6, grain 0.09
  grain     span   amt 0.25, fade 6
  halo      span   amt 1.2, radius 12: blooms the --lights layer before it is screen-blended
Unknown fx (the p5 light cues leak/flare/glints) are skipped here; their frames arrive through --lights.
"""
import argparse
import json
import math
import os
import subprocess
import sys
import time

import cv2
import numpy as np

FPS = 24
MASK64 = (1 << 64) - 1
GOLDEN = 0x9E3779B97F4A7C15
SWS = "scale=flags=accurate_rnd+full_chroma_int+full_chroma_inp"


def fail(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(1)


def opt(value, default):
    """Swift's `value ?? default`: only a missing knob takes the default, 0 stays 0."""
    return default if value is None else value


def wrap64(v):
    """Swift Int (Int64) wrapping arithmetic."""
    v &= MASK64
    return v - (1 << 64) if v >= 1 << 63 else v


class Rand:
    """Deterministic per-frame randomness: SplitMix64, bit for bit the Swift Rand."""

    def __init__(self, a, b=0):
        mixed = wrap64(a * 73_856_093) ^ wrap64(b * 19_349_663)
        self.state = (mixed + GOLDEN) & MASK64

    def next(self):
        self.state = (self.state + GOLDEN) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        z ^= z >> 31
        return (z >> 11) / float(1 << 53)

    def range(self, lo, hi):
        return lo + (hi - lo) * self.next()

    def sign(self):
        return -1.0 if self.next() < 0.5 else 1.0


class Cue:
    """One effect hit: f the beat frame, dur frames from there, pre frames of ramp-in before f."""

    KNOBS = ("pre", "shape", "fade", "amt", "radius", "x", "y", "angle", "color", "hold", "seed", "grain")

    def __init__(self, d):
        try:
            self.fx = d["fx"]
            self.f = int(d["f"])
            self.dur = int(d["dur"])
        except (KeyError, TypeError, ValueError) as e:
            fail(f"bad cue {d}: {e}")
        for k in self.KNOBS:
            setattr(self, k, d.get(k))
        self.first = self.f - opt(self.pre, 0)
        self.last = self.f + self.dur

    def active(self, frame):
        return self.first <= frame < self.last

    def env(self, frame, default_shape="hit", curve=2.2):
        """0...1 strength of the cue at `frame`."""
        if not self.active(frame):
            return 0.0
        if frame < self.f:
            q = (frame - self.first + 1) / (opt(self.pre, 0) + 1)
            return q * q
        t = frame - self.f
        if opt(self.shape, default_shape) == "span":
            fd = max(opt(self.fade, 4), 1)
            return min(1.0, (t + 1) / fd, (self.dur - t) / fd)
        return (1 - t / max(self.dur, 1)) ** curve


class State:
    def __init__(self, frame):
        self.scale, self.anchor, self.dx, self.dy, self.rot = 1.0, (0.5, 0.5), 0.0, 0.0, 0.0
        self.zoom_blur, self.motion, self.motion_angle, self.edge = 0.0, 0.0, 0.0, 0.0
        self.bloom, self.bloom_radius = 0.0, 18.0
        self.flash, self.flash_color = 0.0, (1.0, 0.98, 0.94)  # RGB
        self.dark, self.rgb, self.glitch, self.tv, self.tv_grain, self.grain = 0.0, 0.0, 0.0, 0.0, 0.09, 0.0
        self.halo, self.halo_radius = 0.0, 12.0
        self.seed = frame


def hex_color(value):
    try:
        v = int(str(value).lstrip("#"), 16)
    except ValueError:
        v = 0xFFFFFF
    return (((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255)


def frame_state(frame, cues, w, h):
    """Every active cue adds to the frame's State: a port of Effects.state(frame:cues:)."""
    s = State(frame)
    anchor_weight = 0.0

    def anchor(c, e):
        nonlocal anchor_weight
        if e <= anchor_weight:
            return
        anchor_weight = e
        s.anchor = (opt(c.x, 0.5), opt(c.y, 0.5))

    for c in cues:
        if not c.active(frame):
            continue
        r = Rand(frame, c.f)
        fx = c.fx
        if fx == "punch":
            e = c.env(frame, curve=2.5)
            s.scale *= 1 + opt(c.amt, 0.06) * e
            s.zoom_blur += opt(c.radius, 2) * e * e * e
            s.rgb += 0.002 * e
            anchor(c, e)
        elif fx == "zoom":
            p = (frame - c.f + 1) / max(c.dur, 1)
            e = p * p * (3 - 2 * p)
            s.scale *= 1 + opt(c.amt, 0.08) * max(0.0, e)
            anchor(c, 0.01)
        elif fx == "shake":
            e = c.env(frame, curve=2)
            a = opt(c.amt, 14) * e
            s.dx += r.range(-a, a)
            s.dy += r.range(-a, a)
            s.rot += r.range(-0.006, 0.006) * e
            s.scale *= 1 + 2 * a / h
        elif fx == "whip":
            rad = opt(c.angle, 0) * math.pi / 180
            dist = opt(c.amt, 0.12) * w
            if frame < c.f:
                q = (frame - c.first + 1) / (opt(c.pre, 1) + 1)
                slide, e = dist * q * q * q, q * q
            else:
                q = 1 - (frame - c.f) / max(c.dur, 1)
                slide, e = -dist * q * q * q, q * q
            s.dx += math.cos(rad) * slide
            s.dy += math.sin(rad) * slide
            s.motion += opt(c.radius, 70) * e
            s.motion_angle = rad
            s.scale *= 1 + 0.03 * e
        elif fx == "mblur":
            s.motion += opt(c.amt, 30) * c.env(frame, curve=2)
            s.motion_angle = opt(c.angle, 0) * math.pi / 180
        elif fx == "edgeblur":
            s.edge += opt(c.amt, 10) * c.env(frame, default_shape="span")
        elif fx == "glow":
            s.bloom += opt(c.amt, 1) * c.env(frame, curve=1.6)
            s.bloom_radius = opt(c.radius, 18)
        elif fx == "flash":
            s.flash += opt(c.amt, 1) * c.env(frame, curve=2.8)
            if c.color:
                s.flash_color = hex_color(c.color)
        elif fx == "dark":
            hold = opt(c.hold, 2)
            t = frame - c.f
            if t < 0:
                e = c.env(frame)
            elif t < hold:
                e = 1.0
            else:
                e = (1 - (t - hold) / max(c.dur - hold, 1)) ** 2
            s.dark = max(s.dark, opt(c.amt, 0.94) * e)
        elif fx == "rgb":
            s.rgb += opt(c.amt, 0.006) * c.env(frame, curve=2)
        elif fx == "glitch":
            e = opt(c.amt, 1) * c.env(frame, default_shape="span")
            if r.next() < 0.3:
                e *= 0.15  # flicker: some frames nearly clean
            s.glitch = max(s.glitch, e)
            s.seed = wrap64(frame * 31 + opt(c.seed, c.f))
        elif fx == "tv":
            s.tv = max(s.tv, opt(c.amt, 1) * c.env(frame, default_shape="span"))
            s.tv_grain = opt(c.grain, 0.09)
        elif fx == "grain":
            s.grain = max(s.grain, opt(c.amt, 0.25) * c.env(frame, default_shape="span"))
        elif fx == "halo":
            s.halo = max(s.halo, opt(c.amt, 1.2) * c.env(frame, default_shape="span"))
            s.halo_radius = opt(c.radius, 12)
    if s.tv > 0:
        r = Rand(frame, 777)
        if r.next() < 0.18:
            s.dy += r.sign() * 2 * s.tv  # line jitter
    return s


class Effects:
    """The effect chain for one frame, in the Swift order: camera -> blurs -> light -> p5 light layer -> lens/signal -> dark.
    Images are float32 BGR in 0...1, y down (Core Image is y up, so anchors and bands are flipped where it matters)."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self._edge_mask = None
        self._vignette = None
        self._scanlines = None
        self._bar_x = None

    # MARK: helpers

    def warp(self, img, m):
        return cv2.warpAffine(img, m, (self.w, self.h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)

    @staticmethod
    def about(ax, ay, scale=1.0, rot=0.0, dx=0.0, dy=0.0):
        """Forward affine: translate(-a), rotate, scale, translate(a + d)."""
        c, s = math.cos(rot), math.sin(rot)
        return np.float32([[scale * c, -scale * s, ax + dx - scale * (c * ax - s * ay)],
                           [scale * s, scale * c, ay + dy - scale * (s * ax + c * ay)]])

    def blur(self, img, sigma):
        """Gaussian blur, edge-clamped. Wide blurs run on a downscaled copy (same look, a fraction of the time)."""
        if sigma <= 0.3:
            return img
        if sigma > 10:
            f = max(2, int(sigma // 5))
            small = cv2.resize(img, (max(1, self.w // f), max(1, self.h // f)), interpolation=cv2.INTER_AREA)
            small = cv2.GaussianBlur(small, (0, 0), sigma / f, borderType=cv2.BORDER_REPLICATE)
            return cv2.resize(small, (self.w, self.h), interpolation=cv2.INTER_LINEAR)
        return cv2.GaussianBlur(img, (0, 0), sigma, borderType=cv2.BORDER_REPLICATE)

    def gray_noise(self, seed, salt=99):
        """Uniform grey noise in 0...1, deterministic per (seed, salt)."""
        rng = np.random.default_rng([seed & MASK64, salt])
        return rng.random((self.h, self.w), dtype=np.float32)

    @staticmethod
    def over(top, alpha, bottom):
        return top * alpha + bottom * (1 - alpha)

    @staticmethod
    def screen(top, bottom):
        return top + bottom - top * bottom

    def grid(self):
        ys, xs = np.mgrid[0:self.h, 0:self.w].astype(np.float32)
        return xs, ys

    # MARK: effects

    def zoom_blur(self, img, cx, cy, amount):
        """CIZoomBlur: streaks toward the anchor, about `amount` percent of each pixel's distance from it."""
        n = int(min(32, max(6, amount * 2)))
        acc = np.zeros_like(img)
        for i in range(n):
            acc += self.warp(img, self.about(cx, cy, 1 + (amount / 100.0) * i / (n - 1)))
        return acc / n

    def motion_blur(self, img, radius, angle):
        """CIMotionBlur: a line kernel `radius` px either side of the centre, along `angle` (radians, counter-clockwise)."""
        r = int(min(round(radius), 240))
        if r < 1:
            return img
        size = 2 * r + 1
        k = np.zeros((size, size), np.float32)
        ux, uy = math.cos(angle), -math.sin(angle)
        for t in np.linspace(-r, r, size * 2):
            k[int(round(r + t * uy)), int(round(r + t * ux))] = 1
        k /= k.sum()
        return cv2.filter2D(img, -1, k, borderType=cv2.BORDER_REPLICATE)

    def edge_blur(self, img, radius):
        """Sharp centre, blur growing toward the edges and corners (CIMaskedVariableBlur over a radial gradient)."""
        if self._edge_mask is None:
            xs, ys = self.grid()
            d = np.hypot(xs - self.w / 2, ys - self.h / 2)
            r0, r1 = self.h * 0.36, self.w * 0.62
            self._edge_mask = np.clip((d - r0) / max(r1 - r0, 1), 0, 1)[..., None]
        m = self._edge_mask
        half, full = self.blur(img, radius * 0.5), self.blur(img, radius)
        lo = img + (half - img) * np.clip(m * 2, 0, 1)
        return lo + (full - lo) * np.clip(m * 2 - 1, 0, 1)

    def bloom(self, img, radius, intensity):
        """CIBloom-like glow: a wide blur of the frame screened back over it."""
        k = min(1.0, 0.5 * intensity)
        return self.screen(self.blur(img, radius) * k, img)

    def halo(self, light, amount, radius):
        """Bloom on the premultiplied light layer only: the layer plus a tight and a wide blur of it, clamped to 0...1."""
        out = light + self.blur(light, radius) * amount + self.blur(light, radius * 3.5) * (amount * 0.6)
        return np.clip(out, 0, 1)

    def chroma(self, img, radial, shift):
        """Split R and B: `radial` scales them apart around the centre, `shift` moves them sideways (px)."""
        cx, cy = self.w / 2, self.h / 2
        out = img.copy()
        out[..., 2] = self.warp(np.ascontiguousarray(img[..., 2]), self.about(cx, cy, 1 + radial, dx=shift))
        out[..., 0] = self.warp(np.ascontiguousarray(img[..., 0]), self.about(cx, cy, 1 - radial, dx=-shift))
        return out

    def rows(self, y, bh):
        """A Core Image band (bottom edge y, height bh, y up) as screen rows."""
        top = self.h - y - bh
        return max(0, int(round(top))), min(self.h, int(round(top + bh)))

    def interference(self, img, a, seed):
        """Analog interference: slices shoved sideways, an RGB split, a tinted band and white-noise bars."""
        r = Rand(seed, 4242)
        out = self.chroma(img, 0, (4 + 10 * r.next()) * a)
        base = out.copy()
        cols = np.arange(self.w)
        for _ in range(2 + int(r.next() * 5 * a)):
            bh = r.range(6, 90) * (0.5 + a)
            y = r.range(0, self.h - bh)
            dx = r.sign() * r.range(12, 140) * a
            y0, y1 = self.rows(y, bh)
            out[y0:y1] = base[y0:y1][:, np.clip(cols - int(round(dx)), 0, self.w - 1)]
        if r.next() < 0.6 * a:  # one tinted band (magenta or cyan)
            bh = r.range(20, 120)
            y0, y1 = self.rows(r.range(0, self.h - bh), bh)
            rgb = (1, 0.25, 0.64) if r.next() < 0.5 else (0.2, 0.9, 1)
            tint = np.float32(rgb[::-1]) * (0.35 * a)
            out[y0:y1] = self.screen(tint, out[y0:y1])
        noise = self.gray_noise(seed)[..., None]
        alpha = 0.55 * a
        for _ in range(1 + int(r.next() * 3 * a)):  # white-noise bars
            bh = r.range(2, 18)
            y0, y1 = self.rows(r.range(0, self.h - bh), bh)
            out[y0:y1] = self.over(noise[y0:y1], alpha, out[y0:y1])
        return out

    def old_tv(self, img, a, grain, frame):
        """A worn CRT: softer, faded colour, scanlines, grain, vignette and a slow bright bar rolling down."""
        out = self.blur(img, 1.1 * a)
        out = self.chroma(out, 0, 2.5 * a)
        # Saturation, brightness, contrast and the green-warm phosphor tint are all linear: one 3x4 colour matrix, one pass.
        luma = np.float32([0.0721, 0.7154, 0.2125])  # BGR weights
        sat, bright, contrast = 1 - 0.35 * a, 0.02 * a, 1 + 0.1 * a
        tint = np.float32([1 - 0.08 * a, 1 + 0.02 * a, 1 - 0.02 * a])
        m = sat * np.eye(3, dtype=np.float32) + (1 - sat) * np.outer(np.ones(3, np.float32), luma)
        m = (tint[:, None] * contrast) * m
        bias = tint * (contrast * bright + 0.5 * (1 - contrast))
        out = cv2.transform(out, np.hstack([m, bias[:, None]]).astype(np.float32))
        if grain > 0:
            out = self.over(self.gray_noise(frame)[..., None], grain * a, out)
        y = math.fmod(frame * 9.0, self.h + 400) - 200
        if self._bar_x is None:
            xs = np.arange(self.w, dtype=np.float32)
            self._bar_x = np.exp(-0.5 * ((xs - self.w / 2) / 560.0) ** 2)[None, :]
        ys = np.arange(self.h, dtype=np.float32)
        band = (0.07 * a) * np.exp(-0.5 * ((ys - y) / 28.0) ** 2)[:, None] * self._bar_x
        out = self.screen(band[..., None], out)
        if self._vignette is None:
            xs, ys2 = self.grid()
            d = np.hypot(xs - self.w / 2, ys2 - self.h / 2) / (self.w * 0.55)
            v = np.clip((d - 0.45) / 1.1, 0, 1)
            self._vignette = v * v * (3 - 2 * v)
            self._scanlines = (0.5 + 0.5 * np.cos(2 * np.pi * (ys + 0.5) / 3.0))[:, None]
        # Scanlines and vignette darken multiplicatively: one combined mask.
        return out * ((1 - 0.26 * a * self._scanlines) * (1 - 0.55 * a * self._vignette))[..., None]

    def film_grain(self, img, amount, frame):
        """Soft, slightly clumped grey noise soft-light blended (strongest in midtones), dissolved in by `amount`.
        Soft light here is the Pegtop form, b + (2s - 1) * b * (1 - b): W3C's darkening branch used both ways. For noise
        centred on mid-grey it looks the same as Core Image's and costs a fraction of the sqrt branch."""
        raw = cv2.GaussianBlur(self.gray_noise(frame, 5150), (0, 0), 0.7)
        k = ((2 * raw - 1) * min(1.0, amount))[..., None]
        return img + k * (img - img * img)

    # MARK: one frame

    def apply(self, src, frame, cues, light_path=None):
        s = frame_state(frame, cues, self.w, self.h)
        light = load_light(light_path, self.w, self.h) if light_path else None
        camera = s.scale != 1 or s.dx != 0 or s.dy != 0 or s.rot != 0
        if not (camera or s.zoom_blur > 0.5 or s.motion > 0.5 or s.edge > 0.3 or s.bloom > 0.01 or s.flash > 0.01
                or light is not None or s.rgb > 0.0003 or s.glitch > 0.02 or s.tv > 0.01 or s.grain > 0.005 or s.dark > 0.01):
            return src  # untouched frames stay byte-exact
        img = np.multiply(src, np.float32(1 / 255.0), dtype=np.float32)
        ax, ay = s.anchor[0] * self.w, s.anchor[1] * self.h

        if camera:  # Core Image rotates counter-clockwise with y up; the same turn with y down is -rot
            img = self.warp(img, self.about(ax, ay, s.scale, -s.rot, s.dx, s.dy))
        if s.zoom_blur > 0.5:
            img = self.zoom_blur(img, ax, ay, s.zoom_blur)
        if s.motion > 0.5:
            img = self.motion_blur(img, s.motion, s.motion_angle)
        if s.edge > 0.3:
            img = self.edge_blur(img, s.edge)

        if s.bloom > 0.01:
            img = self.bloom(img, s.bloom_radius, s.bloom)
        if s.flash > 0.01:
            img = img * (2 ** (0.85 * s.flash))
            img = self.over(np.float32(s.flash_color[::-1]), min(0.7, 0.36 * s.flash), img)
        if light is not None:
            if s.halo > 0.01:
                light = self.halo(light, s.halo, s.halo_radius)
            img = self.screen(light[..., :3], img)

        if s.rgb > 0.0003:
            img = self.chroma(img, s.rgb, 0)
        if s.glitch > 0.02:
            img = self.interference(img, s.glitch, s.seed)
        if s.tv > 0.01:
            img = self.old_tv(img, s.tv, s.tv_grain, frame)
        if s.grain > 0.005:
            img = self.film_grain(img, s.grain, frame)
        if s.dark > 0.01:
            img = self.over(np.float32([0.05, 0.02, 0.02]), s.dark, img)
        # convertScaleAbs scales, rounds and saturates in one pass; clamp negatives first (it would mirror them).
        return cv2.convertScaleAbs(np.maximum(img, 0, out=img), alpha=255.0)


def load_light(path, w, h):
    """A p5 light frame (straight-alpha PNG) as premultiplied float BGRA, or None when there is none."""
    if not os.path.isfile(path):
        return None
    data = np.fromfile(path, dtype=np.uint8)  # imdecode: imread cannot open non-ASCII Windows paths
    img = cv2.imdecode(data, cv2.IMREAD_UNCHANGED)
    if img is None:
        fail(f"cannot read light frame {path}")
    scale = 65535.0 if img.dtype == np.uint16 else 255.0
    img = img.astype(np.float32) / scale
    if img.ndim == 2:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    if img.shape[2] == 3:
        img = np.dstack([img, np.ones(img.shape[:2], np.float32)])
    if img.shape[1] != w or img.shape[0] != h:
        img = cv2.resize(img, (w, h), interpolation=cv2.INTER_AREA)
    img[..., :3] *= img[..., 3:4]
    return img


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_packets",
                          "-show_entries", "stream=width,height,nb_read_packets", "-of", "csv=p=0", path],
                         capture_output=True, text=True)
    vals = [int(v) for v in out.stdout.strip().split(",") if v.strip().isdigit()]
    if out.returncode != 0 or len(vals) != 3:
        fail(f"ffprobe failed on {path}: {out.stdout}{out.stderr}")
    return vals[0], vals[1], vals[2]


def read_exact(stream, n):
    buf = stream.read(n)
    return buf if buf is not None and len(buf) == n else None


def parse(argv):
    p = argparse.ArgumentParser(prog="mvfx.py", description="Cue-driven VFX over a finished video (Core Image port).")
    p.add_argument("--in", dest="input", required=True)
    p.add_argument("--cues", required=True)
    p.add_argument("--out")
    p.add_argument("--lights")
    p.add_argument("--stills")
    p.add_argument("--only", default="")
    p.add_argument("--from", dest="start", type=int, default=0)
    p.add_argument("--to", type=int)
    o = p.parse_args(argv)
    if not o.out and not o.stills:
        fail("usage: mvfx.py --in video.mp4 --cues cues.json (--out out.mp4 [--from N --to M] | --stills dir --only 1,2) [--lights dir]")
    o.only = sorted(int(x) for x in o.only.split(",") if x.strip().lstrip("-").isdigit())
    return o


def main(argv=None):
    o = parse(argv if argv is not None else sys.argv[1:])
    try:
        with open(o.cues, encoding="utf-8") as f:
            cues = [Cue(c) for c in json.load(f)["cues"]]
    except (OSError, ValueError, KeyError) as e:
        fail(f"cues {o.cues}: {e}")

    w, h, total = probe(o.input)
    last = min(o.to if o.to is not None else total, total)
    wanted = [f for f in o.only if 0 <= f < total] if o.stills else list(range(o.start, last))
    if not wanted:
        fail("no frames to render")
    if o.stills:
        select = "select='" + "+".join(f"eq(n\\,{f})" for f in wanted) + "'"
    else:
        select = f"trim=start_frame={o.start}:end_frame={last},setpts=PTS-STARTPTS"

    ffmpeg = ["ffmpeg", "-hide_banner", "-v", "error"]
    decoder = subprocess.Popen(ffmpeg + ["-i", o.input, "-vf", f"{select},{SWS},format=bgr24", "-fps_mode", "passthrough",
                                         "-f", "rawvideo", "-pix_fmt", "bgr24", "pipe:1"], stdout=subprocess.PIPE)
    encoder = None
    if o.stills:
        os.makedirs(o.stills, exist_ok=True)
    else:
        t0, length = o.start / FPS, (last - o.start) / FPS
        whole = o.start == 0 and last == total
        audio = ["-i", o.input] if whole else ["-ss", f"{t0:.4f}", "-t", f"{length:.4f}", "-i", o.input]
        encoder = subprocess.Popen(ffmpeg + ["-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{w}x{h}", "-r", str(FPS),
                                             "-i", "pipe:0"] + audio +
                                   ["-map", "0:v:0", "-map", "1:a:0?", "-vf", f"{SWS},format=yuv420p", "-c:v", "libx264",
                                    "-crf", "16", "-preset", "medium", "-r", str(FPS)] +
                                   (["-c:a", "copy"] if whole else ["-c:a", "aac", "-b:a", "256k"]) + [o.out],
                                   stdin=subprocess.PIPE)

    fx = Effects(w, h)
    nbytes = w * h * 3
    started = time.time()
    tty = sys.stderr.isatty()
    try:
        for i, frame in enumerate(wanted):
            buf = read_exact(decoder.stdout, nbytes)
            if buf is None:
                fail(f"decoder ended at frame {frame}")
            src = np.frombuffer(buf, np.uint8).reshape(h, w, 3)
            name = f"{frame:04d}.png"
            light = os.path.join(o.lights, name) if o.lights else None
            img = fx.apply(src, frame, cues, light)
            if o.stills:
                ok, png = cv2.imencode(".png", img)
                if not ok:
                    fail(f"cannot encode still {name}")
                png.tofile(os.path.join(o.stills, name))
            else:
                encoder.stdin.write(img.tobytes() if img is not src else buf)
            if tty and i % 24 == 0:
                sys.stderr.write(f"\rframe {i + 1}/{len(wanted)}")
    except BrokenPipeError:
        fail("encoder pipe closed")
    finally:
        decoder.stdout.close()
    decoder.wait()
    if encoder:
        encoder.stdin.close()
        if encoder.wait() != 0:
            fail(f"encoder failed ({encoder.returncode})")
    if tty:
        sys.stderr.write("\n")
    ms = int((time.time() - started) * 1000)
    print(json.dumps({"out": o.stills or o.out, "frames": len(wanted), "width": w, "height": h, "ms": ms}))


if __name__ == "__main__":
    main()
