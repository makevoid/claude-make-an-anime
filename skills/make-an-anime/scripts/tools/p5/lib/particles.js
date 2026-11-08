// Particles: sparks, explosions (flash + fireball + debris + smoke + shock ring), laser beams, tracer bullets, muzzle
// flashes and impact rings, for any p5 overlay. Generic: nothing here knows about games, units or HUDs.
//
//   const P = Anim.particles;
//   const events = [
//     { type: "laser", id: "l1", at: 0.40, from: [300, 500], to: [900, 420], color: "#5fd0ff" },
//     { type: "tracers", id: "t1", at: 0.20, dur: 1.2, from: [320, 520], to: [880, 440], rate: 14 },
//     { type: "explosion", id: "boom", at: 1.30, x: 900, y: 430, size: 1.4 },
//   ];
//   P.draw(events, t);                    // the picture
//   P.draw(events, t, { mode: "light" }); // only what emits light, on transparent black, for the Swift halo pass
//
// THE DETERMINISM RULE. The overlay may render any frame alone, in any order (previews, --only, a light layer rendered
// later by another process). So no emitter keeps state between frames: every particle is seeded from its emitter's `id`
// and its own index (P.rand(id, k, salt)), and its position, size and colour are closed-form functions of its age
// (t - birth). Never use random(), Math.random(), frameCount or a list that grows frame by frame here.
//
// Every emitter takes `at` (s, when it starts) and an `id` (string or number, unique per emitter: it is the seed).
// Times are in the same clock as the `t` passed to draw (use the shot's local seconds). Coordinates are canvas pixels in
// the current p5 transform, so translate/scale before drawing to follow a scrolling map.
//
// mode "color" (default) draws everything. mode "light" draws only the hot parts (beam cores, muzzle flashes, tracer
// heads, the explosion's flash and fireball, hot sparks) and skips smoke and dark debris. Render the same sketch a second
// time with mode "light" onto a transparent canvas and give those PNGs to mvfx --lights: the halo cue blurs them into a
// bloom and screen-blends them over the frame, so only the light sources glow, not the whole picture.
window.Anim = window.Anim || {};

(() => {
  const TAU = Math.PI * 2;

  // Stable hash of (id, k, salt) -> [0, 1). FNV-1a over the id string, then a 32-bit avalanche.
  const hashStr = (s) => {
    let h = 2166136261 >>> 0;
    s = String(s);
    for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
    return h;
  };
  const rand = (id, k = 0, salt = 0) => {
    let h = (hashStr(id) ^ Math.imul(k + 1, 0x9e3779b1) ^ Math.imul(salt + 7, 0x85ebca77)) >>> 0;
    h ^= h >>> 16; h = Math.imul(h, 0x7feb352d) >>> 0;
    h ^= h >>> 15; h = Math.imul(h, 0x846ca68b) >>> 0;
    h ^= h >>> 16;
    return (h >>> 0) / 4294967296;
  };
  const range = (id, k, salt, lo, hi) => lo + (hi - lo) * rand(id, k, salt);
  const pick = (v, id, k, salt) => (Array.isArray(v) ? range(id, k, salt, v[0], v[1]) : v);

  // Closed-form ballistic motion with linear drag `drag` (1/s) and gravity `g` (px/s², +y down): position after `age` s.
  const fly = (x, y, vx, vy, age, drag, g) => {
    if (drag <= 1e-6) return [x + vx * age, y + vy * age + 0.5 * g * age * age];
    const e = (1 - Math.exp(-drag * age)) / drag;
    return [x + vx * e, y + vy * e + (g / drag) * (age - e)];
  };
  const velAt = (vx, vy, age, drag, g) => {
    const k = Math.exp(-drag * age);
    return [vx * k, vy * k + (drag > 1e-6 ? (g / drag) * (1 - k) : g * age)];
  };

  const hex = (c) => {
    if (Array.isArray(c)) return c;
    const v = parseInt(String(c).replace("#", ""), 16);
    return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
  };
  const rgba = (c, a) => {
    const [r, g, b] = hex(c);
    return `rgba(${r | 0},${g | 0},${b | 0},${Math.max(0, Math.min(1, a)).toFixed(4)})`;
  };
  const mix = (a, b, q) => { const A = hex(a), B = hex(b); return A.map((v, i) => v + (B[i] - v) * q); };
  const clamp01 = (x) => Math.max(0, Math.min(1, x));

  // Soft radial glow at (x, y), radius r. Additive ("lighter") so overlapping light adds up, like light does.
  const glow = (g, x, y, r, c, a, { core = 0.18 } = {}) => {
    if (a <= 0.003 || r <= 0.5) return;
    const grad = g.createRadialGradient(x, y, 0, x, y, r);
    grad.addColorStop(0, rgba(c, a));
    grad.addColorStop(core, rgba(c, a * 0.7));
    grad.addColorStop(1, rgba(c, 0));
    g.fillStyle = grad;
    g.fillRect(x - r, y - r, 2 * r, 2 * r);
  };

  const withCtx = (fn, op = "source-over") => {
    const g = drawingContext;
    g.save();
    g.globalCompositeOperation = op;
    try { fn(g); } finally { g.restore(); }
  };

  const E = {};

  // sparks: a burst of streaks. count 18, speed [180, 620] px/s, life [0.18, 0.5] s, angle 0 (rad, 0 = right),
  // spread TAU (full circle), drag 3, gravity 500, color "#ffd27a", hot "#ffffff", width 2.2, len 0.035 (s of motion per streak).
  E.sparks = (ev, t, mode) => {
    const { id, at = 0, x, y, count = 18, speed = [180, 620], life = [0.18, 0.5], angle = 0, spread = TAU, drag = 3, gravity = 500,
            color = "#ffd27a", hot = "#ffffff", width = 2.2, len = 0.035, alpha = 1 } = ev;
    const age0 = t - at;
    if (age0 < 0 || age0 > (Array.isArray(life) ? life[1] : life) + 0.05) return;
    withCtx((g) => {
      g.lineCap = "round";
      for (let k = 0; k < count; k++) {
        const L = pick(life, id, k, 1), age = age0 - range(id, k, 2, 0, 0.04);
        if (age < 0 || age > L) continue;
        const a = angle + (rand(id, k, 3) - 0.5) * spread, v = pick(speed, id, k, 4);
        const vx = Math.cos(a) * v, vy = Math.sin(a) * v;
        const [x1, y1] = fly(x, y, vx, vy, age, drag, gravity);
        const [x0, y0] = fly(x, y, vx, vy, Math.max(0, age - len), drag, gravity);
        const q = age / L, heat = 1 - q;
        g.strokeStyle = rgba(mix(color, hot, heat * heat), alpha * (1 - q * q));
        g.lineWidth = width * (0.6 + 0.8 * heat);
        g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke();
      }
    }, "lighter");
  };

  // muzzle: a 2-3 frame star flash at the barrel. angle (rad), size 1, color "#ffe7a0", dur 0.08.
  E.muzzle = (ev, t, mode) => {
    const { id, at = 0, x, y, angle = 0, size = 1, color = "#ffe7a0", dur = 0.08 } = ev;
    const age = t - at;
    if (age < 0 || age > dur) return;
    const q = 1 - age / dur, s = size * (0.7 + 0.5 * rand(id, Math.floor(age * 60), 9));
    withCtx((g) => {
      glow(g, x, y, 26 * s, color, 0.9 * q);
      g.translate(x, y); g.rotate(angle);
      g.fillStyle = rgba("#ffffff", q);
      g.beginPath(); g.moveTo(0, -3 * s); g.lineTo(30 * s * q + 8, 0); g.lineTo(0, 3 * s); g.closePath(); g.fill();
      g.fillStyle = rgba(color, 0.8 * q);
      g.beginPath(); g.moveTo(-2, -7 * s); g.lineTo(14 * s, 0); g.lineTo(-2, 7 * s); g.closePath(); g.fill();
    }, "lighter");
  };

  // ring: an expanding impact/shock ring. radius 60, dur 0.35, color "#bfe8ff", weight 5, squash 0.55 (y scale, ground plane).
  E.ring = (ev, t, mode) => {
    const { x, y, at = 0, radius = 60, dur = 0.35, color = "#bfe8ff", weight = 5, squash = 0.55, alpha = 0.9 } = ev;
    const age = t - at;
    if (age < 0 || age > dur) return;
    const q = age / dur, r = radius * (1 - Math.pow(1 - q, 3));
    withCtx((g) => {
      g.strokeStyle = rgba(color, alpha * (1 - q));
      g.lineWidth = weight * (1 - q * 0.7);
      g.beginPath(); g.ellipse(x, y, r, r * squash, 0, 0, TAU); g.stroke();
    }, "lighter");
  };

  // laser: a beam from `from` to `to`. dur 0.16 (s on), grow 0.035 (s for the head to reach the target), color "#5fd0ff",
  // width 5, flicker 0.25, hit true (sparks + glow at the target), muzzle true.
  E.laser = (ev, t, mode) => {
    const { id, at = 0, from, to, dur = 0.16, grow = 0.035, color = "#5fd0ff", width = 5, flicker = 0.25, hit = true, muzzle = true } = ev;
    const age = t - at;
    if (age < 0) return;
    const [x0, y0] = from, [x1, y1] = to;
    if (hit && age < dur + 0.4) E.sparks({ id: `${id}:hit`, at: at + grow, x: x1, y: y1, count: 10, speed: [120, 420], life: [0.1, 0.3],
                                           color, hot: "#ffffff", width: 1.8, gravity: 300 }, t, mode);
    if (age > dur) return;
    const head = clamp01(age / grow), tail = clamp01((age - dur + grow) / grow);
    const hx = x0 + (x1 - x0) * head, hy = y0 + (y1 - y0) * head;
    const tx = x0 + (x1 - x0) * tail, ty = y0 + (y1 - y0) * tail;
    const fl = 1 - flicker * rand(id, Math.floor(age * 48), 5);
    withCtx((g) => {
      g.lineCap = "round";
      g.strokeStyle = rgba(color, 0.35 * fl); g.lineWidth = width * 3.2;
      g.beginPath(); g.moveTo(tx, ty); g.lineTo(hx, hy); g.stroke();
      g.strokeStyle = rgba(color, 0.9 * fl); g.lineWidth = width;
      g.beginPath(); g.moveTo(tx, ty); g.lineTo(hx, hy); g.stroke();
      g.strokeStyle = rgba("#ffffff", 0.95 * fl); g.lineWidth = Math.max(1, width * 0.35);
      g.beginPath(); g.moveTo(tx, ty); g.lineTo(hx, hy); g.stroke();
      if (head >= 1) glow(g, x1, y1, width * 7, color, 0.8 * fl);
    }, "lighter");
    if (muzzle) E.muzzle({ id: `${id}:mz`, at, x: x0, y: y0, angle: Math.atan2(y1 - y0, x1 - x0), size: width / 5, color }, t, mode);
  };

  // tracers: a stream of bullets from `from` to `to`. dur 1 (s of firing), rate 12 (shots/s), speed 2200 px/s,
  // color "#ffd36b", len 34 (px streak), spread 14 (px of scatter at the target), jitter 0.3 (of a shot period),
  // muzzle true, hit true (a small spark where each round lands).
  E.tracers = (ev, t, mode) => {
    const { id, at = 0, dur = 1, rate = 12, from, to, speed = 2200, color = "#ffd36b", len = 34, spread = 14, jitter = 0.3,
            muzzle = true, hit = true, width = 2.4 } = ev;
    if (t < at) return;
    const n = Math.ceil(dur * rate);
    for (let k = 0; k < n; k++) {
      const fire = at + (k + (rand(id, k, 1) - 0.5) * jitter) / rate;
      const age = t - fire;
      if (age < 0) continue;
      const tx = to[0] + (rand(id, k, 2) - 0.5) * spread * 2, ty = to[1] + (rand(id, k, 3) - 0.5) * spread;
      const dist = Math.hypot(tx - from[0], ty - from[1]), flight = dist / speed;
      if (muzzle) E.muzzle({ id: `${id}:m${k}`, at: fire, x: from[0], y: from[1], angle: Math.atan2(ty - from[1], tx - from[0]), size: 0.55, color, dur: 0.05 }, t, mode);
      if (age <= flight) {
        const q = age / flight, ux = (tx - from[0]) / dist, uy = (ty - from[1]) / dist;
        const hx = from[0] + (tx - from[0]) * q, hy = from[1] + (ty - from[1]) * q;
        withCtx((g) => {
          g.lineCap = "round";
          g.strokeStyle = rgba(color, 0.9); g.lineWidth = width;
          g.beginPath(); g.moveTo(hx - ux * len, hy - uy * len); g.lineTo(hx, hy); g.stroke();
          g.fillStyle = rgba("#ffffff", 1); g.beginPath(); g.arc(hx, hy, width * 0.7, 0, TAU); g.fill();
        }, "lighter");
      } else if (hit && age < flight + 0.2) {
        E.sparks({ id: `${id}:h${k}`, at: fire + flight, x: tx, y: ty, count: 4, speed: [80, 260], life: [0.06, 0.16], color, width: 1.4, gravity: 200 }, t, mode);
      }
    }
  };

  // explosion: flash + fireball + debris + smoke + shock ring + scorch. size 1 (scale; 1 ≈ 90 px fireball),
  // palette { flash "#fff6d8", fire ["#ffe08a", "#ff8a2a", "#c0381c"], smoke "#2c2a2a" }, debris 22, smokeCount 9,
  // ring true, dur 1.6 (s until the smoke is gone).
  E.explosion = (ev, t, mode) => {
    const { id, at = 0, x, y, size = 1, debris = 22, smokeCount = 9, ring = true, dur = 1.6,
            flash = "#fff6d8", fire = ["#ffe08a", "#ff8a2a", "#c0381c"], smoke = "#2c2a2a" } = ev;
    const age = t - at;
    if (age < 0 || age > dur) return;
    const s = size;
    // Smoke: grey puffs that rise, grow and thin out. Dark, so never in the light layer.
    if (mode !== "light") {
      withCtx((g) => {
        for (let k = 0; k < smokeCount; k++) {
          const born = 0.08 + rand(id, k, 11) * 0.25, a = age - born;
          if (a < 0) continue;
          const L = dur - born, q = clamp01(a / L);
          const ang = rand(id, k, 12) * TAU, d = (20 + 40 * rand(id, k, 13)) * s * (1 - Math.exp(-3 * a));
          const px = x + Math.cos(ang) * d + 18 * s * a, py = y + Math.sin(ang) * d * 0.55 - 55 * s * a;
          const r = (22 + 30 * rand(id, k, 14)) * s * (0.5 + 0.9 * Math.sqrt(q));
          const grad = g.createRadialGradient(px, py, 0, px, py, r);
          const al = 0.55 * Math.sin(Math.PI * Math.min(1, q * 1.15)) * (0.6 + 0.4 * rand(id, k, 15));
          grad.addColorStop(0, rgba(smoke, al)); grad.addColorStop(0.6, rgba(smoke, al * 0.6)); grad.addColorStop(1, rgba(smoke, 0));
          g.fillStyle = grad; g.fillRect(px - r, py - r, 2 * r, 2 * r);
        }
      });
    }
    // Flash: one white-hot frame or two, then gone.
    withCtx((g) => {
      const fq = clamp01(1 - age / 0.12);
      glow(g, x, y, 170 * s, flash, 0.85 * fq * fq, { core: 0.1 });
      // Fireball: hot blobs that swell, cool from yellow to red and fade.
      const fb = clamp01(age / 0.55);
      for (let k = 0; k < 7; k++) {
        const ang = rand(id, k, 21) * TAU, d = 28 * s * rand(id, k, 22) * Math.sqrt(fb);
        const px = x + Math.cos(ang) * d, py = y + Math.sin(ang) * d * 0.6 - 10 * s * fb;
        const r = (34 + 26 * rand(id, k, 23)) * s * (0.35 + 0.9 * Math.sqrt(fb));
        const heat = 1 - fb;
        const c = heat > 0.5 ? mix(fire[1], fire[0], (heat - 0.5) * 2) : mix(fire[2], fire[1], heat * 2);
        glow(g, px, py, r, c, 0.9 * heat * (mode === "light" ? 0.9 : 1), { core: 0.3 });
      }
    }, "lighter");
    if (ring) E.ring({ x, y: y + 6 * s, at, radius: 120 * s, dur: 0.32, color: "#ffe2b0", weight: 6 * s, alpha: 0.75 }, t, mode);
    // Debris: hot fragments thrown out with gravity; they glow while hot, then dark chunks (colour mode only).
    for (let k = 0; k < debris; k++) {
      const L = range(id, k, 31, 0.35, 0.9), a = age - range(id, k, 32, 0, 0.03);
      if (a < 0 || a > L) continue;
      const ang = -Math.PI / 2 + (rand(id, k, 33) - 0.5) * Math.PI * 1.7, v = range(id, k, 34, 160, 520) * s;
      const vx = Math.cos(ang) * v, vy = Math.sin(ang) * v * 0.8;
      const [px, py] = fly(x, y, vx, vy, a, 1.6, 900 * s);
      const q = a / L, hot = clamp01(1 - q * 2.2);
      if (hot > 0) {
        const [ux, uy] = velAt(vx, vy, a, 1.6, 900 * s), sp = Math.hypot(ux, uy) || 1;
        withCtx((g) => {
          g.strokeStyle = rgba(mix(fire[1], "#ffffff", hot * 0.6), hot); g.lineWidth = 2.2 * s; g.lineCap = "round";
          g.beginPath(); g.moveTo(px - (ux / sp) * 9 * s, py - (uy / sp) * 9 * s); g.lineTo(px, py); g.stroke();
        }, "lighter");
      } else if (mode !== "light") {
        withCtx((g) => { g.fillStyle = rgba("#1b1714", 1 - q); g.fillRect(px - 2 * s, py - 2 * s, 4 * s, 3 * s); });
      }
    }
  };

  // scorch: a dark burn mark left on the ground from `at` on (colour mode only). radius 46.
  E.scorch = (ev, t, mode) => {
    const { x, y, at = 0, radius = 46, alpha = 0.6 } = ev;
    if (t < at || mode === "light") return;
    const a = alpha * clamp01((t - at) / 0.2);
    withCtx((g) => {
      g.translate(x, y); g.scale(1, 0.55);
      const grad = g.createRadialGradient(0, 0, 0, 0, 0, radius);
      grad.addColorStop(0, `rgba(10,8,6,${a})`); grad.addColorStop(0.7, `rgba(20,14,10,${a * 0.5})`); grad.addColorStop(1, "rgba(0,0,0,0)");
      g.fillStyle = grad; g.fillRect(-radius, -radius, 2 * radius, 2 * radius);
    });
  };

  // The ground parts first (scorch), then everything else in list order.
  const draw = (events, t, { mode = "color" } = {}) => {
    for (const ev of events) if (ev.type === "scorch") E.scorch(ev, t, mode);
    for (const ev of events) {
      if (ev.type === "scorch") continue;
      const fn = E[ev.type];
      if (!fn) throw new Error(`Anim.particles: unknown emitter type "${ev.type}" (${Object.keys(E).join(", ")})`);
      fn(ev, t, mode);
    }
  };

  // How strongly the light events hit at t (0..1+): drive a screen flash, a shake or a sound cue from the same list.
  const intensity = (events, t) => events.reduce((sum, ev) => {
    const age = t - (ev.at ?? 0);
    if (ev.type === "explosion" && age >= 0) return sum + (ev.size ?? 1) * Math.exp(-age / 0.12);
    return sum;
  }, 0);

  Anim.particles = { draw, emitters: E, rand, range, fly, intensity, rgba, glow };
})();
