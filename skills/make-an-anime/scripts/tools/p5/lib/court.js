// Basketball courts as Orbital Command maps: a half court (the drills) and a full court (the match), with glowing
// lines on steel deck plates, a dribbled ball, a pass, the sprite-to-face-icon swap, and the "fill the spaces" drill.
// Needs mission.js (frame, floor, units, icons, fog), rts.js and particles.js.
//
//   const C = Anim.court;
//   const geo = C.half(box);          // 15 m across, 14 m deep, the basket at the top: geo.px(u), geo.py(v), geo.m
//   const geo = C.full(box);          // 28 m long, 15 m across, baskets left and right: geo.px(x), geo.py(y)
//   C.lines(geo);                     // the painted lines, glowing
//   C.fromHalf([u, v])                // a half-court spot (attacking the right basket) on the full court
//   C.ball(t, x, y, { dribble })      // the ball at a hand, bouncing when dribbled
//   C.drill(R, f, local, cfg)         // the whole "fill the spaces" view (see below)
//
// Everything is a pure function of t, as in particles.js: the drill's crawler is re-simulated from 0 each frame.
window.Anim = window.Anim || {};

(() => {
  const C = {};
  const M = () => Anim.mission;
  const clamp01 = (x) => Math.max(0, Math.min(1, x));
  const TAU = Math.PI * 2;
  const LINE = "rgba(90,190,255,0.9)";

  C.half = (box) => { const m = box.h / 14; return { kind: "half", box, m, px: (u) => box.x + u * m, py: (v) => box.y + v * m }; };
  C.full = (box) => { const m = box.w / 28; return { kind: "full", box, m, px: (x) => box.x + x * m, py: (y) => box.y + y * m }; };
  // A spot of the half court (u across, v out from the baseline) on the full court, attacking the right-hand basket.
  C.fromHalf = ([u, v]) => [28 - v, u];

  C.lines = (geo, { color = LINE, width: lw = 4 } = {}) => {
    const { px, py, m } = geo, G = (d) => M().glowStroke(d, { color, width: lw, blur: 12, core: "rgba(230,248,255,0.9)" });
    if (geo.kind === "half") {
      // the same lines the drills always had: side lines, the key, the arc, the basket
      G((c) => c.rect(px(0), py(0), 15 * m, 14 * m));
      G((c) => c.rect(px(5.05), py(0), 4.9 * m, 5.8 * m));
      G((c) => c.arc(px(7.5), py(1.575), 6.25 * m, 0, Math.PI));
      G((c) => { c.moveTo(px(7.5) + 0.225 * m, py(1.575)); c.arc(px(7.5), py(1.575), 0.225 * m, 0, TAU); });
      G((c) => { c.moveTo(px(6.6), py(1.2)); c.lineTo(px(8.4), py(1.2)); });
      return;
    }
    G((c) => c.rect(px(0), py(0), 28 * m, 15 * m));
    G((c) => { c.moveTo(px(14), py(0)); c.lineTo(px(14), py(15)); });
    G((c) => { c.moveTo(px(14) + 1.8 * m, py(7.5)); c.arc(px(14), py(7.5), 1.8 * m, 0, TAU); });
    for (const side of [0, 1]) {
      const X = (x) => px(side ? 28 - x : x), dir = side ? -1 : 1;
      G((c) => c.rect(Math.min(X(0), X(5.8)), py(5.05), 5.8 * m, 4.9 * m));
      G((c) => { c.moveTo(X(5.8) + dir * 1.8 * m, py(7.5)); c.arc(X(5.8), py(7.5), 1.8 * m, side ? Math.PI : 0, side ? 3 * Math.PI : TAU); });
      // the three-point line: straight in the corners, then the arc (6.75 m from the basket); a is the arc's half-angle
      const a = Math.asin(6.6 / 6.75), hx = X(1.575);
      G((c) => {
        c.moveTo(X(0), py(0.9)); c.lineTo(X(2.99), py(0.9));
        if (side) c.arc(hx, py(7.5), 6.75 * m, -Math.PI + a, Math.PI - a, true);
        else c.arc(hx, py(7.5), 6.75 * m, -a, a, false);
        c.lineTo(X(0), py(14.1));
      });
      G((c) => { c.moveTo(hx + 0.225 * m, py(7.5)); c.arc(hx, py(7.5), 0.225 * m, 0, TAU); });
      G((c) => { c.moveTo(X(1.2), py(6.6)); c.lineTo(X(1.2), py(8.4)); });
    }
  };

  // The ball: orange, with seams, a shadow, and a hot rim light. dribble: bounces from the hand (h px above the floor)
  // to the floor, `hz` bounces a second.
  C.ball = (t, x, y, { r = 13, dribble = false, hz = 2.6, h = 46, glow = true } = {}) => {
    const g = drawingContext;
    const lift = dribble ? h * (1 - Math.abs(Math.cos(Math.PI * hz * t))) ** 0.8 : 0;
    const squash = dribble && lift < 4 ? 0.82 : 1;
    g.save();
    g.fillStyle = `rgba(0,0,0,${0.45 - 0.25 * lift / Math.max(1, h)})`;
    g.beginPath(); g.ellipse(x, y + r * 0.6, r * (1.05 - 0.3 * lift / Math.max(1, h)), r * 0.35, 0, 0, TAU); g.fill();
    g.translate(x, y - lift); g.scale(1 / squash ** 0.5, squash);
    if (glow) { g.shadowColor = "rgba(255,140,40,0.9)"; g.shadowBlur = 14; }
    const gr = g.createRadialGradient(-r * 0.35, -r * 0.4, r * 0.1, 0, 0, r);
    gr.addColorStop(0, "#ffb15a"); gr.addColorStop(1, "#d0561a");
    g.fillStyle = gr; g.beginPath(); g.arc(0, 0, r, 0, TAU); g.fill();
    g.shadowBlur = 0; g.strokeStyle = "rgba(40,14,0,0.75)"; g.lineWidth = 1.6;
    g.beginPath(); g.moveTo(-r, 0); g.lineTo(r, 0); g.moveTo(0, -r); g.lineTo(0, r); g.stroke();
    g.restore();
  };

  // A pass from a to b over `dur` s from `at`: the ball's position, with a little loft, or null outside it.
  C.pass = (t, at, dur, a, b, loft = 30) => {
    const q = (t - at) / dur;
    if (q < 0 || q > 1) return null;
    const e = q * q * (3 - 2 * q);
    return [a[0] + (b[0] - a[0]) * e, a[1] + (b[1] - a[1]) * e - loft * Math.sin(Math.PI * q)];
  };

  // Formation steps: dots run from one formation to the next at k * step, taking `move` s, then hold.
  C.steps = (forms, t, { step, move, lag = 0 }) => {
    const tt = Math.max(0, t - lag);
    const k = Math.min(Math.floor(tt / step), forms.length - 1);
    const p = k === 0 ? 0 : Anim.ease.inOutCubic(clamp01((tt - k * step) / move));
    const prev = forms[Math.max(k - 1, 0)], next = forms[k];
    return { k, p, dots: next.map((d, i) => [prev[i][0] + (d[0] - prev[i][0]) * p, prev[i][1] + (d[1] - prev[i][1]) * p]),
             moving: next.map((d, i) => p > 0 && p < 1 && Math.hypot(d[0] - prev[i][0], d[1] - prev[i][1]) > 0.05),
             dir: next.map((d, i) => Math.sign(d[0] - prev[i][0]) || 1) };
  };

  // A side panel of face icons: the squad, a lost one greyed and crossed. faces: [{img, name, lost}].
  C.squadPanel = (R, f, x, y, w, h, faces, { title = "SQUAD", s = 1.2, t = 0, extra } = {}) => {
    const g = drawingContext;
    g.save(); g.fillStyle = "#05080c"; g.fillRect(x, y, w, h); g.restore();
    const alive = faces.filter((q) => !q.lost).length;
    Anim.rts.ui.styledText(`${title}  ${alive}/${faces.length}`, x + w / 2, y + 34, { font: f.logo, size: 24, style: "#cfe8ff", glow: "rgba(60,160,255,0.8)", blur: 8 });
    const cols = 2, cw = w / cols, sz = Math.min(cw - 40, 104), rh = sz + 26;
    faces.forEach((q, i) => {
      const cx = x + cw * (i % cols) + cw / 2, cy = y + 76 + sz / 2 + Math.floor(i / cols) * rh;
      g.save(); g.globalAlpha = q.lost ? 0.35 : 1; g.filter = q.lost ? "grayscale(1)" : "none";
      g.drawImage(q.img.canvas || q.img.elt || q.img, cx - sz / 2, cy - sz / 2, sz, sz);
      g.restore();
      if (q.lost) {
        g.save(); g.strokeStyle = "rgba(255,60,40,0.95)"; g.lineWidth = 6; g.shadowColor = "rgba(255,40,20,1)"; g.shadowBlur = 10;
        const d = sz * 0.3; g.beginPath(); g.moveTo(cx - d, cy - d); g.lineTo(cx + d, cy + d); g.moveTo(cx + d, cy - d); g.lineTo(cx - d, cy + d); g.stroke(); g.restore();
      }
      Anim.rts.ui.hpBar(cx, cy + sz / 2 + 8, sz * 0.8, q.lost ? 0 : 1, [60, 230, 80]);
    });
    if (extra) extra(x, y + h - 70, w);
    M().bezel(R, { x, y, w, h }, { s });
  };

  // ---- the drill: "fill the spaces" ------------------------------------------------------------------------------
  // cfg: { forms (4 formations of 8 [u, v]), step, move, faces (8 names, the squad), crawlerFrom [u, v], speed (m/s),
  //        chalk (v of the chalk line, optional), ball ([u, v], optional), line (the mission line), title }
  // One red crawler hunts the nearest trooper. Bunched, they are easy; spread, it has to run and the one it chases steps
  // away, so it runs further and cannot get them all. Its metres run are counted on the panel.
  const simCache = {};
  C.drillSim = (cfg, t) => {
    const key = JSON.stringify([cfg.forms, cfg.step, cfg.move, cfg.crawlerFrom, cfg.speed]);
    let sim = simCache[key];
    if (!sim) {
      const dt = 1 / 96, T = 8;
      const n = cfg.forms[0].length, off = Array.from({ length: n }, () => [0, 0]);
      let c = [...cfg.crawlerFrom], run = 0, pause = 0, target = -1;
      const lost = [], frames = [];
      for (let s = 0, tt = 0; tt <= T; s++, tt = s * dt) {
        const base = C.steps(cfg.forms, tt, cfg).dots, spread = tt >= cfg.step;
        const pos = base.map((b, i) => [b[0] + off[i][0], b[1] + off[i][1]]);
        const aliveIdx = pos.map((_, i) => i).filter((i) => !lost.some((q) => q.i === i));
        // the nearest one is the target
        let best = -1, bd = Infinity;
        for (const i of aliveIdx) { const d = Math.hypot(pos[i][0] - c[0], pos[i][1] - c[1]); if (d < bd) { bd = d; best = i; } }
        target = best;
        if (pause > 0) pause -= dt;
        else if (best >= 0) {
          const [dx, dy] = [pos[best][0] - c[0], pos[best][1] - c[1]], d = Math.hypot(dx, dy);
          if (d < 0.55) { lost.push({ i: best, at: tt, x: pos[best][0], y: pos[best][1] }); pause = 0.45; }
          else { const v = Math.min(cfg.speed * dt, d); c = [c[0] + dx / d * v, c[1] + dy / d * v]; run += v; }
        }
        // spread out, the one it closes on steps away from it (inside the half); the others drift back to their space
        for (const i of aliveIdx) {
          const [dx, dy] = [pos[i][0] - c[0], pos[i][1] - c[1]], d = Math.hypot(dx, dy) || 1;
          if (spread && i === target && d < 2.2) {
            const v = cfg.speed * 0.92 * dt;
            off[i][0] += dx / d * v; off[i][1] += dy / d * v;
            off[i][0] = Math.max(0.6 - base[i][0], Math.min(14.4 - base[i][0], off[i][0]));
            off[i][1] = Math.max(0.6 - base[i][1], Math.min(13.4 - base[i][1], off[i][1]));
          } else { off[i][0] *= 0.985; off[i][1] *= 0.985; }
        }
        frames.push({ c: [...c], run, target, off: off.map((o) => [...o]), lost: lost.length });
      }
      sim = simCache[key] = { dt, frames, lost };
    }
    const fr = sim.frames[Math.min(sim.frames.length - 1, Math.max(0, Math.round(t / sim.dt)))];
    return { ...fr, lostList: sim.lost.slice(0, fr.lost) };
  };

  C.drill = (R, f, local, cfg) => {
    const box = cfg.box || { x: 300, y: 170, w: 750, h: 700 };
    const s = 1.4;
    M().begin(R, box, { s });
    const geo = C.half(box), { px, py, m } = geo;
    M().floor(box, { seed: "court", tile: 50, tint: [36, 44, 54], light: 1.2 });
    // the half's paint, a shade lighter in the key
    drawingContext.save(); drawingContext.fillStyle = "rgba(70,150,255,0.10)"; drawingContext.fillRect(px(5.05), py(0), 4.9 * m, 5.8 * m); drawingContext.restore();
    C.lines(geo);
    if (cfg.chalk != null) M().glowStroke((c) => { c.moveTo(px(0), py(cfg.chalk)); c.lineTo(px(15), py(cfg.chalk)); }, { color: "rgba(255,255,255,0.85)", width: 6, blur: 6 });

    const st = C.steps(cfg.forms, local, cfg), sim = C.drillSim(cfg, local);
    const dots = st.dots.map((d, i) => [d[0] + sim.off[i][0], d[1] + sim.off[i][1]]);
    const lostAt = (i) => sim.lostList.find((q) => q.i === i);
    // fog: the floor near a trooper is lit, the rest stays dim, so the empty spaces show
    // a ring on each space as a trooper arrives in it
    if (st.k > 0 && local - st.k * cfg.step > cfg.move) {
      const r = clamp01((local - st.k * cfg.step - cfg.move) / 0.35);
      for (const [i, [a, b]] of cfg.forms[st.k].entries()) if (!lostAt(i)) M().glowStroke((c) => c.arc(px(a), py(b), 14 + 34 * r, 0, TAU), { color: `rgba(255,255,255,${0.85 * (1 - r)})`, width: 3, blur: 8 });
    }
    if (cfg.ball) {
      C.ball(local, px(cfg.ball[0]), py(cfg.ball[1]), { r: 12 });
      const settle = clamp01((local - 2.2) / 0.3);
      if (settle > 0) { const r = (local * 1.1) % 1; M().glowStroke((c) => c.arc(px(cfg.ball[0]), py(cfg.ball[1]), 16 + 40 * r, 0, TAU), { color: `rgba(255,140,40,${0.9 * (1 - r) * settle})`, width: 3, blur: 8 }); }
    }
    // the crawler's chase line to its target
    const tgt = sim.target;
    if (tgt >= 0 && !lostAt(tgt)) M().orderPath(local, [[px(sim.c[0]), py(sim.c[1])], [px(dots[tgt][0]), py(dots[tgt][1])]], { color: "rgba(255,70,50,0.75)", a: 0.8 });
    // units, back to front
    const list = dots.map((d, i) => ({ i, v: d[1] })).concat([{ i: -1, v: sim.c[1] }]).sort((a, b) => a.v - b.v);
    for (const o of list) {
      if (o.i === -1) {
        const dir = tgt >= 0 ? Math.sign(dots[tgt][0] - sim.c[0]) || -1 : -1;
        M().unit(R, "crawler", px(sim.c[0]), py(sim.c[1]) + 26, 98, { dir, hp: 1, hpColour: [230, 60, 50], bob: Math.abs(Math.sin(local * 12)) * 3 });
        continue;
      }
      const L = lostAt(o.i);
      if (L && local - L.at > 0.5) continue;
      const [a, b] = dots[o.i];
      M().unit(R, "trooper", px(a), py(b) + 24, 60, { dir: st.dir[o.i], sel: !L, alpha: L ? 1 - clamp01((local - L.at) / 0.5) : 1,
        hp: L ? 0 : 1, bob: st.moving[o.i] ? Math.abs(Math.sin(local * 14 + o.i)) * 3 : 0 });
    }
    // each loss: a small blast where it happened
    const ev = sim.lostList.flatMap((q, j) => [
      { type: "explosion", id: `drill-boom-${j}`, at: q.at, x: px(q.x), y: py(q.y), size: 0.6, smokeCount: 3 },
      { type: "sparks", id: `drill-sparks-${j}`, at: q.at, x: px(q.x), y: py(q.y) - 10, count: 18, speed: [160, 520], life: [0.2, 0.5], color: "#ffcf70" },
    ]);
    Anim.particles.draw(ev, local);
    M().end(R, box, { t: local, s, fonts: f, title: cfg.title || "TRAINING", headerY: 4, line: cfg.line });
    // the squad panel, right of the court
    const B = { x: box.x + box.w + 150, y: box.y - 10, w: 380, h: box.h + 20 };
    C.squadPanel(R, f, B.x, B.y, B.w, B.h, cfg.faces.map((n, i) => ({ img: R.faces[n], lost: !!lostAt(i) })), {
      t: local, extra: (x, y, w) => {
        Anim.rts.ui.styledText(`CRAWLER RAN  ${sim.run.toFixed(0)} m`, x + w / 2, y + 26, { font: f.logo, size: 22, style: "#ff8a6a", glow: "rgba(255,60,40,0.8)", blur: 8 });
      },
    });
    return { sim, st };
  };

  // ---- the match: players as units, then as face icons -----------------------------------------------------------
  // One player at its spot (canvas px): the team's sprite (blue troopers; the other team as tinted crawlers) or, once
  // `icons` is on, its face icon on a team ring. o: { team: "blue"|"yellow"|"red", face (image), dir, moving, t, i, pop }
  C.player = (R, x, y, { team = "blue", face = null, icons = false, dir = 1, moving = false, t = 0, i = 0, size = 1, pop = 1 } = {}) => {
    const bob = moving ? Math.abs(Math.sin(t * 13 + i * 1.7)) * 3 : 0;
    if (icons && face) {
      const ring = team === "blue" ? "rgba(70,170,255,0.95)" : team === "yellow" ? "rgba(255,200,40,0.95)" : "rgba(255,70,50,0.95)";
      const glow = team === "blue" ? "rgba(60,150,255,0.8)" : "rgba(255,180,30,0.85)";
      M().icon(face, x, y - 30 * size - bob, 74 * size, { ring, glow, pop });
      return { x, y, top: y - 70 * size, hand: [x + 26 * size, y - 4] };
    }
    if (team === "blue") {
      const u = M().unit(R, "trooper", x, y, 62 * size, { dir, sel: true, ring: "rgba(70,170,255,0.95)", bob });
      return { ...u, hand: [x + dir * 22 * size, y - 4] };
    }
    const u = M().unit(R, "crawler", x, y, 96 * size, { dir, sel: true, ring: team === "yellow" ? "rgba(255,200,40,0.9)" : "rgba(255,70,50,0.9)", tint: team === "yellow" ? "yellow" : null, bob });
    return { ...u, hand: [x, y] };
  };

  Anim.court = C;
})();
