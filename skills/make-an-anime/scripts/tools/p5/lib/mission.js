// Mission maps: the small top-down maps of a 2004 RTS (a campaign briefing, a zoomed minimap, a micro drill), drawn in
// the Orbital Command look. The frame is the HUD console's own minimap bezel (9-sliced from console.png, so it stays
// sharp at any size), the floor is steel deck plating, lines glow, units are the game's sprites with selection rings,
// and there is fog of war, objective beacons, face-icon badges, a flash, and a typed mission line.
// Needs rts.js (Anim.rts.load gives R; Anim.rts.ui gives the shared text, plate and cursor helpers) and particles.js.
//
//   const R = await Anim.rts.load({ dir: "/output/ui-rts-assets", units: ["trooper", "crawler"] });
//   R.faces = await Anim.mission.loadFaces("/output/ui-rts-assets/faces", ["pilot", "rival"]);   // optional
//   const box = { x: 250, y: 60, w: 1420, h: 820 };                    // the map's screen rectangle (inside the bezel)
//   Anim.mission.begin(R, box, { t });                                  // background and console plate, clip to the map
//   Anim.mission.floor(box, { seed: "school", tile: 64 });             // deck plates
//   ...lines, walls, units, fog, beacons, in screen pixels...
//   Anim.mission.end(R, box, { t, fonts, title: "MISSION 3", line: { text: "Reach the stairs", at: 0.2 } });
//
// Everything is a pure function of t (see particles.js, the determinism rule): no state between frames.
window.Anim = window.Anim || {};

(() => {
  const TAU = Math.PI * 2;
  const M = {};
  const UI = () => Anim.rts.ui;
  const P = () => Anim.particles;
  const clamp01 = (x) => Math.max(0, Math.min(1, x));

  // The minimap bezel in console.png (its own pixels): the outer edge of the steel frame, and the frame's widths
  // (left, top, right, bottom) up to the black screen. Corners are cut `corner` px deep so the rivets stay whole.
  M.BEZEL = null; // Set from the measured console art, or pass R.bezel. No project-specific geometry.

  // Which way each sprite faces as drawn on its sheet: the blue faction faces right, the red one left.
  M.FACING = { trooper: 1, walker: 1, tank: 1, gunship: 1, spider: -1, crawler: -1, skiff: -1, stilt: -1 };

  // Tints for a unit drawn in another team's colour (canvas filters on the red sprites).
  M.TINT = {
    yellow: "sepia(0.9) saturate(3.2) hue-rotate(8deg) brightness(1.12)",
    red: "none",
  };

  M.loadFaces = async (dir, names) => {
    const out = {};
    for (const n of names) out[n] = await loadImage(`${dir}/${n}.png`);
    return out;
  };

  // ---- frame ------------------------------------------------------------------------------------------------------

  // The bezel round a screen rectangle, 9-sliced from the console: s scales the frame's thickness (2 ≈ 70 px).
  M.bezel = (R, r, { s = 2 } = {}) => {
    const bezel = R.bezel || M.BEZEL;
    if (!bezel) throw new Error("Anim.mission: set R.bezel {box, inset, corner} from your console image");
    const [bx, by, bw, bh] = bezel.box, [il, it, ir, ib] = bezel.inset, c = bezel.corner;
    const g = drawingContext, img = R.console.canvas || R.console.elt || R.console;
    const ox = r.x - il * s, oy = r.y - it * s, ow = r.w + (il + ir) * s, oh = r.h + (it + ib) * s;
    const cs = c * s;
    const sx = [bx, bx + c, bx + bw - c, bx + bw], dx = [ox, ox + cs, ox + ow - cs, ox + ow];
    const sy = [by, by + c, by + bh - c, by + bh], dy = [oy, oy + cs, oy + oh - cs, oy + oh];
    g.save();
    g.imageSmoothingQuality = "high";
    for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) {
      if (i === 1 && j === 1) continue; // the screen itself
      const w = sx[i + 1] - sx[i], h = sy[j + 1] - sy[j];
      g.drawImage(img, sx[i], sy[j], w, h, dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j]);
    }
    g.restore();
    return { x: ox, y: oy, w: ow, h: oh };
  };

  // The background behind the map: dark gunmetal with a soft top light, and a recessed plate round the bezel.
  M.begin = (R, r, { t = 0, s = 2, plate = true } = {}) => {
    const g = drawingContext;
    background(0);
    const bg = g.createRadialGradient(width / 2, height * 0.42, 80, width / 2, height / 2, width * 0.75);
    bg.addColorStop(0, "#1d242d"); bg.addColorStop(1, "#05070a");
    g.save(); g.fillStyle = bg; g.fillRect(0, 0, width, height);
    // faint panel seams across the background
    g.strokeStyle = "rgba(255,255,255,0.035)"; g.lineWidth = 2;
    for (let x = 0; x < width; x += 160) { g.beginPath(); g.moveTo(x, 0); g.lineTo(x, height); g.stroke(); }
    g.restore();
    if (plate) {
      const bezel = R.bezel || M.BEZEL;
      if (!bezel) throw new Error("Anim.mission: set R.bezel {box, inset, corner} from your console image");
      const [il, it, ir, ib] = bezel.inset, pad = 26;
      UI().bevelRect(r.x - il * s - pad, r.y - it * s - pad, r.w + (il + ir) * s + 2 * pad, r.h + (it + ib) * s + 2 * pad,
        { face: "#222932", light: "#5d6978", dark: "#07090c", cut: 18 });
    }
    g.save(); g.fillStyle = "#000"; g.fillRect(r.x, r.y, r.w, r.h);
    g.beginPath(); g.rect(r.x, r.y, r.w, r.h); g.clip();
  };

  // Close the map: the clip ends, then the bezel, an optional header (the logo plate and a title) and the mission line.
  M.end = (R, r, { t = 0, s = 2, fonts, title, line, logo = true, logoText = "ORBITAL", headerY } = {}) => {
    drawingContext.restore();
    // inner shadow on the screen, under the bezel
    const g = drawingContext;
    g.save();
    const sh = 26;
    for (const [x, y, w, h, x0, y0, x1, y1] of [[r.x, r.y, r.w, sh, 0, r.y, 0, r.y + sh], [r.x, r.y, sh, r.h, r.x, 0, r.x + sh, 0]]) {
      const gr = g.createLinearGradient(x0, y0, x1, y1); gr.addColorStop(0, "rgba(0,0,0,0.65)"); gr.addColorStop(1, "rgba(0,0,0,0)");
      g.fillStyle = gr; g.fillRect(x, y, w, h);
    }
    g.restore();
    const B = M.bezel(R, r, { s });
    if (fonts && logo) {
      const hy = headerY ?? Math.max(0, B.y - 74);
      UI().logoPlate(t, { fonts, logo: { text: logoText, sub: title || "BATTLE" } }, width / 2, hy);
    }
    if (fonts && line) M.missionLine(t, line.text, { fonts, x: B.x + 40, y: line.y ?? Math.min(height - 46, B.y + B.h + 34), at: line.at ?? 0, label: line.label });
    return B;
  };

  // ---- ground -----------------------------------------------------------------------------------------------------

  const floorCache = {};
  // Steel deck plates over a rectangle, the same every frame for a seed.
  M.floor = (r, { seed = "deck", tile = 64, tint = [27, 32, 39], light = 1 } = {}) => {
    const key = `${seed}|${r.w | 0}|${r.h | 0}|${tile}|${tint}|${light}`;
    let c = floorCache[key];
    if (!c) {
      c = document.createElement("canvas"); c.width = Math.ceil(r.w); c.height = Math.ceil(r.h);
      const g = c.getContext("2d");
      const R = (k, s) => P().rand(seed, k, s);
      for (let y = 0, j = 0; y < c.height; y += tile, j++) for (let x = 0, i = 0; x < c.width; x += tile, i++) {
        const k = j * 997 + i, v = (R(k, 1) - 0.5) * 14 * light;
        const [cr, cg, cb] = tint;
        g.fillStyle = `rgb(${cr + v},${cg + v},${cb + v * 1.1})`; g.fillRect(x, y, tile, tile);
        // bevel: light top and left, dark bottom and right
        g.fillStyle = "rgba(255,255,255,0.06)"; g.fillRect(x, y, tile, 2); g.fillRect(x, y, 2, tile);
        g.fillStyle = "rgba(0,0,0,0.55)"; g.fillRect(x, y + tile - 2, tile, 2); g.fillRect(x + tile - 2, y, 2, tile);
        // rivets, some plates with a tread pattern, a rare grate
        g.fillStyle = "rgba(160,175,190,0.22)";
        for (const [a, b] of [[6, 6], [tile - 8, 6], [6, tile - 8], [tile - 8, tile - 8]]) g.fillRect(x + a, y + b, 2, 2);
        const kind = R(k, 2);
        if (kind < 0.18) {
          g.strokeStyle = "rgba(255,255,255,0.05)"; g.lineWidth = 2;
          for (let d = 10; d < tile - 6; d += 9) { g.beginPath(); g.moveTo(x + d, y + 10); g.lineTo(x + d - 5, y + tile - 10); g.stroke(); }
        } else if (kind > 0.96) {
          g.fillStyle = "rgba(0,0,0,0.45)";
          for (let d = 12; d < tile - 10; d += 7) g.fillRect(x + 12, y + d, tile - 24, 3);
        }
        // grime
        g.fillStyle = `rgba(0,0,0,${0.12 * R(k, 3)})`; g.fillRect(x, y, tile, tile);
      }
      floorCache[key] = c;
    }
    drawingContext.drawImage(c, r.x, r.y, r.w, r.h);
  };

  // Stroke a path with a glow: draw(path) builds it on the context. Two passes: a wide soft glow, then the crisp line.
  M.glowStroke = (draw, { color = "rgba(70,170,255,0.95)", width: lw = 4, blur = 14, core = null } = {}) => {
    const g = drawingContext;
    g.save();
    g.lineCap = "round"; g.lineJoin = "round";
    g.shadowColor = color; g.shadowBlur = blur; g.strokeStyle = color; g.lineWidth = lw;
    g.beginPath(); draw(g); g.stroke();
    g.shadowBlur = 0;
    if (core) { g.strokeStyle = core; g.lineWidth = Math.max(1, lw * 0.35); g.beginPath(); draw(g); g.stroke(); }
    g.restore();
  };

  // A wall: a thick steel strip with a lit top edge and a cobalt trim line, between two points.
  M.wall = (x0, y0, x1, y1, { w = 14, trim = "rgba(60,150,255,0.85)" } = {}) => {
    const g = drawingContext;
    g.save(); g.lineCap = "square";
    g.strokeStyle = "#0a0d11"; g.lineWidth = w + 6; g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke();
    g.strokeStyle = "#4a5562"; g.lineWidth = w; g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke();
    g.strokeStyle = "#8e9bab"; g.lineWidth = 2; g.beginPath(); g.moveTo(x0, y0 - w / 2 + 2); g.lineTo(x1, y1 - w / 2 + 2); g.stroke();
    g.shadowColor = trim; g.shadowBlur = 10; g.strokeStyle = trim; g.lineWidth = 2;
    g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke();
    g.restore();
  };

  // A rectangle of walls with optional gaps: gaps [{ side: "top"|"bottom"|"left"|"right", at: px from the side's start, w }].
  M.room = (x, y, w, h, { gaps = [], ...o } = {}) => {
    const side = (name, ax, ay, bx, by) => {
      const len = Math.hypot(bx - ax, by - ay), ux = (bx - ax) / len, uy = (by - ay) / len;
      const cuts = gaps.filter((q) => q.side === name).sort((a, b) => a.at - b.at);
      let s = 0;
      for (const q of cuts) { if (q.at > s) M.wall(ax + ux * s, ay + uy * s, ax + ux * q.at, ay + uy * q.at, o); s = q.at + q.w; }
      if (s < len) M.wall(ax + ux * s, ay + uy * s, bx, by, o);
    };
    side("top", x, y, x + w, y); side("bottom", x, y + h, x + w, y + h);
    side("left", x, y, x, y + h); side("right", x + w, y, x + w, y + h);
  };

  // Fog of war over a rectangle: black (alpha `dark`) except soft round holes round each source [x, y, r].
  const fogCanvas = document.createElement("canvas");
  M.fog = (r, sources, { dark = 1, soft = 0.38, color = "0,0,0" } = {}) => {
    const c = fogCanvas;
    if (c.width !== width || c.height !== height) { c.width = width; c.height = height; }
    const g = c.getContext("2d");
    g.globalCompositeOperation = "source-over"; g.clearRect(0, 0, c.width, c.height);
    g.fillStyle = `rgba(${color},${dark})`; g.fillRect(r.x, r.y, r.w, r.h);
    g.globalCompositeOperation = "destination-out";
    for (const [x, y, rad] of sources) {
      const gr = g.createRadialGradient(x, y, 0, x, y, rad);
      gr.addColorStop(0, "rgba(0,0,0,1)"); gr.addColorStop(1 - soft, "rgba(0,0,0,1)"); gr.addColorStop(1, "rgba(0,0,0,0)");
      g.fillStyle = gr; g.fillRect(x - rad, y - rad, 2 * rad, 2 * rad);
    }
    drawingContext.drawImage(c, 0, 0);
  };

  // ---- units and markers ------------------------------------------------------------------------------------------

  // A unit sprite at its foot point (x, y), w px wide. dir 1 faces right, -1 left. sel: a ring in `ring` colour.
  M.unit = (R, kind, x, y, w, { dir = 1, sel = false, ring = "rgba(70,255,100,0.95)", tint = null, alpha = 1, hp = null, hpColour = [60, 230, 80], bob = 0 } = {}) => {
    const img = R.units[kind];
    const h = (w * img.height) / img.width, g = drawingContext;
    g.save(); g.globalAlpha = alpha;
    g.fillStyle = "rgba(0,0,0,0.5)"; g.beginPath(); g.ellipse(x, y + 2, w * 0.42, w * 0.16, 0, 0, TAU); g.fill();
    if (sel) { g.strokeStyle = ring; g.lineWidth = 2.5; g.beginPath(); g.ellipse(x, y + 2, w * 0.52, w * 0.21, 0, 0, TAU); g.stroke(); }
    const flip = dir !== (M.FACING[kind] ?? 1);
    g.translate(x, y - bob);
    if (flip) g.scale(-1, 1);
    if (tint && M.TINT[tint]) g.filter = M.TINT[tint];
    g.drawImage(img.canvas || img.elt || img, -w / 2, -h, w, h);
    g.filter = "none";
    g.restore();
    if (hp != null) UI().hpBar(x, y - h - bob - 10, Math.min(w * 0.8, 56), hp, hpColour);
    return { x, y, w, h, top: y - h - bob };
  };

  // A face icon badge (the SD unit icons) centred at (x, y), s px square, with a team ring under it.
  M.icon = (img, x, y, s, { ring = "rgba(70,255,100,0.95)", glow = "rgba(60,150,255,0.8)", alpha = 1, pop = 1 } = {}) => {
    const g = drawingContext, k = s * pop;
    g.save(); g.globalAlpha = alpha;
    g.fillStyle = "rgba(0,0,0,0.5)"; g.beginPath(); g.ellipse(x, y + k * 0.56, k * 0.46, k * 0.14, 0, 0, TAU); g.fill();
    if (ring) { g.strokeStyle = ring; g.lineWidth = 3; g.beginPath(); g.ellipse(x, y + k * 0.56, k * 0.55, k * 0.18, 0, 0, TAU); g.stroke(); }
    g.shadowColor = glow; g.shadowBlur = 16;
    g.drawImage(img.canvas || img.elt || img, x - k / 2, y - k / 2, k, k);
    g.restore();
  };

  // A pop for something appearing at `at`: 0 before, overshoots to about 1.15, settles at 1 by at + dur.
  M.pop = (t, at, dur = 0.28) => {
    const q = (t - at) / dur;
    if (q <= 0) return 0;
    if (q >= 1) return 1;
    return 1 + 0.15 * Math.sin(q * Math.PI) - (1 - q) * (1 - q) * (1 - q);
  };

  // A full-screen flash at `at`: white, peaking in 2 frames, gone by at + dur. Returns its strength (0..1).
  M.flash = (t, at, { dur = 0.4, color = "255,255,255", max = 1 } = {}) => {
    const age = t - at;
    if (age < -0.08 || age > dur) return 0;
    const a = max * (age < 0 ? clamp01((age + 0.08) / 0.08) : Math.exp(-age / (dur * 0.32)));
    const g = drawingContext;
    g.save(); g.globalCompositeOperation = "lighter"; g.fillStyle = `rgba(${color},${a})`; g.fillRect(0, 0, width, height); g.restore();
    return a;
  };

  // An objective beacon: a turning diamond, rings rising out of it, a soft column of light.
  M.beacon = (t, x, y, { color = [255, 200, 60], size = 1 } = {}) => {
    const g = drawingContext, [r, gg, b] = color;
    g.save();
    const col = g.createLinearGradient(0, y - 160 * size, 0, y);
    col.addColorStop(0, `rgba(${r},${gg},${b},0)`); col.addColorStop(1, `rgba(${r},${gg},${b},0.28)`);
    g.fillStyle = col; g.fillRect(x - 16 * size, y - 160 * size, 32 * size, 160 * size);
    for (let i = 0; i < 2; i++) {
      const q = ((t * 0.9 + i * 0.5) % 1);
      g.strokeStyle = `rgba(${r},${gg},${b},${0.9 * (1 - q)})`; g.lineWidth = 3;
      g.beginPath(); g.ellipse(x, y, (14 + 46 * q) * size, (6 + 18 * q) * size, 0, 0, TAU); g.stroke();
    }
    g.translate(x, y - 26 * size - 4 * Math.sin(t * 3)); g.scale(Math.cos(t * 2.4) * size, size);
    g.shadowColor = `rgba(${r},${gg},${b},1)`; g.shadowBlur = 14;
    g.fillStyle = `rgba(${r},${gg},${b},0.95)`;
    g.beginPath(); g.moveTo(0, -16); g.lineTo(11, 0); g.lineTo(0, 16); g.lineTo(-11, 0); g.closePath(); g.fill();
    g.restore();
  };

  // A path the player ordered: dashes moving along a polyline towards its end, with a chevron at the end.
  M.orderPath = (t, pts, { color = "rgba(80,255,110,0.9)", a = 1 } = {}) => {
    const g = drawingContext;
    g.save(); g.globalAlpha = a; g.strokeStyle = color; g.lineWidth = 3; g.setLineDash([14, 12]); g.lineDashOffset = -t * 60;
    g.beginPath(); pts.forEach(([x, y], i) => (i ? g.lineTo(x, y) : g.moveTo(x, y))); g.stroke();
    g.setLineDash([]);
    const [ax, ay] = pts[pts.length - 2], [bx, by] = pts[pts.length - 1], an = Math.atan2(by - ay, bx - ax);
    g.lineWidth = 4; g.beginPath();
    g.moveTo(bx - 18 * Math.cos(an - 0.5), by - 18 * Math.sin(an - 0.5)); g.lineTo(bx, by); g.lineTo(bx - 18 * Math.cos(an + 0.5), by - 18 * Math.sin(an + 0.5));
    g.stroke(); g.restore();
  };

  // ---- text -------------------------------------------------------------------------------------------------------

  // The mission line: a steel plate with a small label and the objective typed out from `at`, 38 characters a second.
  M.missionLine = (t, str, { fonts, x, y, at = 0, label = "OBJECTIVE", cps = 38 } = {}) => {
    const n = Math.max(0, Math.floor((t - at) * cps));
    if (t < at) return;
    const shown = str.slice(0, n), f = fonts.logo, g = drawingContext;
    textFont(f); textSize(26);
    const w = textWidth(str) + 250, h = 56;
    UI().bevelRect(x, y - h / 2, w, h, { face: "#141a21", light: "#56616e", dark: "#05070a", cut: 10 });
    g.save(); g.fillStyle = "rgba(255,190,60,0.95)"; g.fillRect(x + 12, y - 16, 6, 32); g.restore();
    UI().styledText(label, x + 30, y + 1, { font: f, size: 16, style: "#ffc45a", align: [LEFT, CENTER], spacing: 3, glow: "rgba(255,170,40,0.8)", blur: 8, outline: "#140c00", weight: 2 });
    UI().styledText(shown + (n < str.length && Math.floor(t * 6) % 2 ? "_" : ""), x + 190, y + 1, { font: f, size: 26, style: "#e8f2ff", align: [LEFT, CENTER], glow: "rgba(60,160,255,0.7)", blur: 8 });
  };

  // A small tag over a unit or icon, e.g. a name or "#14": dark plate, team colour edge.
  M.tag = (str, x, y, { fonts, colour = "#3aa0ff", size = 18 } = {}) => {
    const f = fonts.logo;
    textFont(f); textSize(size);
    const w = textWidth(str) + 18, h = size + 10, g = drawingContext;
    g.save(); g.fillStyle = "rgba(4,8,14,0.82)"; g.fillRect(x - w / 2, y - h / 2, w, h); g.fillStyle = colour; g.fillRect(x - w / 2, y + h / 2 - 3, w, 3); g.restore();
    UI().styledText(str, x, y, { font: f, size, style: "#eef6ff" });
  };

  Anim.mission = M;
})();
