// RTS game screen: a 2004-style real-time strategy game on a PC monitor, composed from generated art sheets (terrain,
// HUD console frame, unit sprites, command icons, a unit portrait) with every readable word and number drawn here.
// Needs particles.js (Anim.particles) for the shooting and the explosions.
//
//   const R = await Anim.rts.load({ dir: "/output/ui-rts-assets", units: ["trooper", ...], icons: ["move", ...] });
//   const game = { ...the scene's battle: units, events, cursor, selection... (see "The game object" below) };
//   Anim.rts.screen(t, R, game);                     // the picture
//   Anim.rts.screen(t, R, game, { mode: "light" });  // only the light (lasers, flashes, eyes), for the mvfx halo pass
//
// Assets (tools/python/cut_sheets.py makes them from the five sheets): map.jpg (terrain), console.png (the HUD frame with
// its screens cut transparent) + console_slots.json (their rectangles), units/<name>.png, icons/<name>.png, portrait.png.
//
// Layout: the console is drawn full width along the bottom at its own aspect. Its screens are classified from the slot
// list: the large ones, left to right, are game.hud.screens (default ["portrait", "minimap", "info", "gauge"]), and the
// small equal ones are the command-card sockets, row by row. Everything under a screen is drawn first, then the frame.
//
// The game object (all times in the same seconds as t; world coordinates are terrain pixels after map.scale):
//   title "Orbital Command"           window title bar text           top 44 (title bar height)
//   fonts { ui, uiBold, logo }         p5 fonts                         logo { text: "ORBITAL", sub: "BATTLE" }
//   map { scale 0.9, cam(t) -> [x, y] }   camera = world point at the viewport's top-left
//   kinds { name: { w, muzzle: [fx, fy], air } }   draw width (px) and gun position as fractions of w from the foot point
//   units [{ id, kind, team, at(t) -> [x, y] foot point, dies (s) }]   team "blue" (the player) or "red"; facing is the sprite's
//   selected(t, u) -> bool              the player's selection           target(t) -> unit id | null (red ring + hp bar)
//   events [particle events]            world coordinates (see particles.js)
//   markers [{ at, x, y, kind: "attack" | "move" }]   click markers on the ground
//   drag(t) -> null | { a: [x, y], b: [x, y] }   selection box, screen coordinates
//   cursor(t) -> { x, y, down, mode: "arrow" | "target" }   screen coordinates
//   resources(t) -> [{ icon: "crystal" | "gas" | "supply", text }]   timer(t) -> "23:41"
//   commands [12 icon names]  pressed [{ name, at }]   gauge(t) -> 0..1
//   pings [{ at, x, y, color }]         minimap alerts (world)           portrait { eyes: [[x, y], ...] in portrait.png px,
//                                                                         eye "#ffa040", talk: [[from, to], ...] }
//   vision { radius 360 }               fog of war around the player's units
//   alert(t) -> null | { text, sub, a }   a warning across the battlefield ("Your base is under attack"), a = 0..1
//   iconOf(u) -> image | null           a unit's tile in the info screen (e.g. a player's face icon) instead of its sprite
window.Anim = window.Anim || {};

(() => {
  const TAU = Math.PI * 2;
  const P = () => Anim.particles;
  const TEAM = { blue: [60, 150, 255], red: [255, 70, 60] };
  const clamp01 = (x) => Math.max(0, Math.min(1, x));

  const loadJSON = async (url) => {
    const r = await fetch(url);
    if (!r.ok) throw new Error(`Anim.rts: ${url} ${r.status}`);
    return r.json();
  };

  Anim.rts = {};

  Anim.rts.load = async ({ dir, units = [], icons = [] }) => {
    const R = { dir, units: {}, icons: {} };
    R.map = await loadImage(`${dir}/map.jpg`);
    R.console = await loadImage(`${dir}/console.png`);
    R.slots = await loadJSON(`${dir}/console_slots.json`);
    R.portrait = await loadImage(`${dir}/portrait.png`);
    for (const n of units) R.units[n] = await loadImage(`${dir}/units/${n}.png`);
    for (const n of icons) R.icons[n] = await loadImage(`${dir}/icons/${n}.png`);
    R.fog = document.createElement("canvas");
    return R;
  };

  // Screen rectangles of the console and its screens, for a canvas width W and height H.
  Anim.rts.layout = (R, game, W = width, H = height) => {
    const s = R.slots, k = W / s.w, y0 = H - s.h * k;
    const rect = ([x, y, w, h]) => ({ x: x * k, y: y0 + y * k, w: w * k, h: h * k });
    const areas = s.slots.map((r) => r[2] * r[3]).sort((a, b) => a - b);
    const small = areas[Math.floor(areas.length / 4)];
    const big = s.slots.filter((r) => r[2] * r[3] > small * 3).sort((a, b) => a[0] - b[0]);
    const sockets = s.slots.filter((r) => r[2] * r[3] <= small * 3)
      .sort((a, b) => (Math.abs(a[1] - b[1]) > a[3] / 2 ? a[1] - b[1] : a[0] - b[0]));
    const names = game.hud?.screens || ["portrait", "minimap", "info", "gauge"];
    const screens = Object.fromEntries(big.map((r, i) => [names[i] || `screen${i}`, rect(r)]));
    return { k, y0, top: y0 + s.top * k, screens, sockets: sockets.map(rect), W, H };
  };

  // A unit's geometry at t: foot point, sprite box, gun and body centre, in world coordinates.
  Anim.rts.geom = (R, game, u, t) => {
    const kind = game.kinds[u.kind], img = R.units[u.kind];
    const [x, y] = u.at(t);
    const w = kind.w, h = (w * img.height) / img.width;
    const lift = kind.air ? 46 + 4 * Math.sin(t * 3 + u.id.length) : 0;
    const dir = u.team === "blue" ? 1 : -1;
    const m = kind.muzzle || [0.45, -0.55];
    return { x, y, w, h, lift, img, dir, air: !!kind.air,
             muzzle: [x + dir * m[0] * w, y - lift + m[1] * h], center: [x, y - lift - h * 0.42] };
  };

  Anim.rts.alive = (u, t) => u.dies == null || t < u.dies;

  // ---- drawing helpers -------------------------------------------------------------------------------------------

  const bevelRect = (x, y, w, h, { face = "#2a3038", light = "#8b97a6", dark = "#0b0e12", cut = 6 } = {}) => {
    const g = drawingContext;
    g.save();
    g.beginPath();
    g.moveTo(x + cut, y); g.lineTo(x + w - cut, y); g.lineTo(x + w, y + cut); g.lineTo(x + w, y + h - cut);
    g.lineTo(x + w - cut, y + h); g.lineTo(x + cut, y + h); g.lineTo(x, y + h - cut); g.lineTo(x, y + cut); g.closePath();
    const grad = g.createLinearGradient(0, y, 0, y + h);
    grad.addColorStop(0, light); grad.addColorStop(0.08, face); grad.addColorStop(0.92, face); grad.addColorStop(1, dark);
    g.fillStyle = grad; g.fill();
    g.strokeStyle = "rgba(0,0,0,0.85)"; g.lineWidth = 2; g.stroke();
    g.restore();
  };

  // Text with a canvas fill style (gradient) or a colour, optional glow and outline. p5 caches its fill, so the
  // context's fillStyle is set after fill() and right before text().
  const styledText = (str, x, y, { font, size, style = "#fff", glow = null, blur = 0, outline = null, weight = 0, align = [CENTER, CENTER], spacing = 0 }) => {
    textFont(font); textSize(size); textAlign(...align);
    const g = drawingContext;
    g.save();
    g.letterSpacing = `${spacing}px`;
    if (outline) {
      noFill(); stroke(outline); strokeWeight(weight);
      if (glow) { g.shadowColor = glow; g.shadowBlur = blur; }
      text(str, x, y);
      g.shadowBlur = 0;
    }
    noStroke(); fill(255);
    g.fillStyle = style;
    text(str, x, y);
    g.restore();
  };

  // The game logo plate: a chamfered steel plate hanging from the top edge, the title in a heavy chiselled face with a
  // steel bevel and an electric-blue glow.
  const logoPlate = (t, game, cx, y) => {
    const { text: main = "ORBITAL", sub = "BATTLE" } = game.logo || {};
    const f = game.fonts.logo;
    textFont(f); textSize(46);
    drawingContext.letterSpacing = "3px";
    const tw = textWidth(main);
    drawingContext.letterSpacing = "0px";
    const w = tw + 230, h = 78, x = cx - w / 2;
    const g = drawingContext;
    // plate
    g.save();
    g.beginPath();
    g.moveTo(x, y); g.lineTo(x + w, y); g.lineTo(x + w - 34, y + h); g.lineTo(x + 34, y + h); g.closePath();
    const pg = g.createLinearGradient(0, y, 0, y + h);
    pg.addColorStop(0, "#1a2029"); pg.addColorStop(0.5, "#2b333e"); pg.addColorStop(1, "#11151b");
    g.fillStyle = pg; g.fill();
    g.strokeStyle = "#6d7b8c"; g.lineWidth = 2; g.stroke();
    g.beginPath(); g.moveTo(x + 40, y + h - 7); g.lineTo(x + w - 40, y + h - 7);
    g.strokeStyle = `rgba(70,160,255,${0.55 + 0.25 * Math.sin(t * 4)})`; g.lineWidth = 2; g.stroke();
    g.restore();
    // title: blue glow behind a dark outline, then a chrome gradient face, then a thin top highlight
    const ty = y + 32;
    const chrome = g.createLinearGradient(0, ty - 24, 0, ty + 22);
    chrome.addColorStop(0, "#ffffff"); chrome.addColorStop(0.32, "#c9d3df"); chrome.addColorStop(0.5, "#5d6876");
    chrome.addColorStop(0.56, "#3a4350"); chrome.addColorStop(0.78, "#aab6c4"); chrome.addColorStop(1, "#e9f1fb");
    const pulse = 0.75 + 0.25 * Math.sin(t * 2.6);
    styledText(main, cx, ty, { font: f, size: 46, style: chrome, outline: "#041226", weight: 7, glow: `rgba(40,150,255,${pulse})`, blur: 26, spacing: 3 });
    // the sub line between two blue rules
    const sy = y + 63;
    styledText(sub, cx, sy, { font: f, size: 19, style: "#8fd0ff", glow: "rgba(40,150,255,0.9)", blur: 10, outline: "#03101e", weight: 3, spacing: 9 });
    textFont(f); textSize(19); g.letterSpacing = "9px";
    const sw = textWidth(sub); g.letterSpacing = "0px";
    g.save();
    g.strokeStyle = "rgba(80,170,255,0.85)"; g.lineWidth = 2;
    g.beginPath(); g.moveTo(cx - sw / 2 - 90, sy); g.lineTo(cx - sw / 2 - 16, sy); g.moveTo(cx + sw / 2 + 10, sy); g.lineTo(cx + sw / 2 + 84, sy); g.stroke();
    g.restore();
  };

  const resourceIcon = (kind, x, y) => {
    const g = drawingContext;
    g.save();
    if (kind === "crystal") {
      g.beginPath(); g.moveTo(x, y - 13); g.lineTo(x + 8, y - 2); g.lineTo(x + 3, y + 12); g.lineTo(x - 5, y + 10); g.lineTo(x - 8, y - 3); g.closePath();
      const gr = g.createLinearGradient(x - 8, y - 13, x + 8, y + 12); gr.addColorStop(0, "#d8f4ff"); gr.addColorStop(0.5, "#3aa4ff"); gr.addColorStop(1, "#0b3d9a");
      g.fillStyle = gr; g.shadowColor = "rgba(60,170,255,0.9)"; g.shadowBlur = 10; g.fill();
    } else if (kind === "gas") {
      g.beginPath(); g.arc(x, y + 3, 9, 0, TAU); g.moveTo(x - 6, y - 4); g.lineTo(x, y - 14); g.lineTo(x + 6, y - 4);
      g.fillStyle = "#3fe07a"; g.shadowColor = "rgba(60,240,120,0.9)"; g.shadowBlur = 10; g.fill();
      g.fillStyle = "rgba(255,255,255,0.7)"; g.beginPath(); g.arc(x - 3, y + 1, 2.5, 0, TAU); g.fill();
    } else {
      g.beginPath(); g.moveTo(x - 10, y + 10); g.lineTo(x - 10, y - 2); g.lineTo(x, y - 12); g.lineTo(x + 10, y - 2); g.lineTo(x + 10, y + 10); g.closePath();
      g.fillStyle = "#c8d2de"; g.shadowColor = "rgba(120,180,255,0.8)"; g.shadowBlur = 8; g.fill();
      g.fillStyle = "#1a3a6a"; g.fillRect(x - 4, y + 1, 8, 9);
    }
    g.restore();
  };

  const topHud = (t, game, L) => {
    const top = game.top ?? 44, f = game.fonts;
    // left: menu buttons and the game clock
    ["MENU", "ALLIES"].forEach((label, i) => {
      const x = 14 + i * 118, y = top + 8;
      bevelRect(x, y, 108, 34, { face: "#262d36", light: "#7d8a99", cut: 5 });
      styledText(label, x + 54, y + 18, { font: f.logo, size: 16, style: "#b9c7d6", spacing: 2 });
    });
    bevelRect(254, top + 8, 104, 34, { face: "#11161c", light: "#4c5866", cut: 5 });
    styledText(game.timer(t), 306, top + 25, { font: f.logo, size: 20, style: "#e6f0ff", glow: "rgba(60,160,255,0.7)", blur: 6 });
    logoPlate(t, game, L.W / 2, top);
    // right: resources
    const res = game.resources(t);
    let x = L.W - 22;
    textFont(f.logo); textSize(22);
    for (let i = res.length - 1; i >= 0; i--) {
      const r = res[i], tw = Math.max(textWidth(r.text), 52);
      const bx = x - tw - 44;
      drawingContext.save(); drawingContext.fillStyle = "rgba(4,8,14,0.55)"; drawingContext.fillRect(bx - 6, top + 8, tw + 54, 34); drawingContext.restore();
      resourceIcon(r.icon, bx + 12, top + 25);
      styledText(r.text, bx + 32, top + 26, { font: f.logo, size: 22, style: "#e8f2ff", align: [LEFT, CENTER], glow: null });
      x = bx - 16;
    }
  };

  // ---- the battlefield --------------------------------------------------------------------------------------------

  const groundMarker = (t, m) => {
    const age = t - m.at;
    if (age < 0 || age > 0.45) return;
    const q = age / 0.45, g = drawingContext;
    g.save();
    g.translate(m.x, m.y); g.scale(1, 0.55);
    if (m.kind === "attack") {
      const r = 34 * (1 - q) + 8;
      g.strokeStyle = `rgba(255,60,50,${1 - q})`; g.lineWidth = 4;
      g.beginPath(); g.arc(0, 0, r, 0, TAU); g.stroke();
      g.beginPath(); g.moveTo(-r * 0.5, -r * 0.5); g.lineTo(r * 0.5, r * 0.5); g.moveTo(r * 0.5, -r * 0.5); g.lineTo(-r * 0.5, r * 0.5); g.stroke();
    } else {
      const r = 10 + 30 * q;
      g.strokeStyle = `rgba(80,255,110,${1 - q})`; g.lineWidth = 4;
      g.beginPath(); g.arc(0, 0, r, 0, TAU); g.stroke();
    }
    g.restore();
  };

  const hpBar = (x, y, w, hp, colour) => {
    const n = Math.max(4, Math.round(w / 9)), sw = w / n;
    noStroke(); fill(0, 0, 0, 200); rect(x - w / 2 - 2, y - 2, w + 4, 9);
    for (let i = 0; i < n; i++) {
      const on = (i + 0.5) / n <= hp;
      fill(...(on ? colour : [50, 20, 20])); rect(x - w / 2 + i * sw + 0.5, y, sw - 1.5, 5);
    }
  };

  const drawUnits = (t, R, game) => {
    const live = game.units.filter((u) => Anim.rts.alive(u, t)).map((u) => ({ u, G: Anim.rts.geom(R, game, u, t) }))
      .sort((a, b) => a.G.y - b.G.y);
    const target = game.target?.(t);
    const g = drawingContext;
    for (const { u, G } of live) {
      // shadow
      g.save(); g.fillStyle = "rgba(0,0,0,0.45)"; g.beginPath();
      g.ellipse(G.x + (G.air ? 22 : 0), G.y + (G.air ? 10 : 2), G.w * (G.air ? 0.32 : 0.42), G.w * (G.air ? 0.12 : 0.16), 0, 0, TAU); g.fill(); g.restore();
      // selection ring
      const sel = u.team === "blue" && game.selected(t, u), tgt = u.id === target;
      if (sel || tgt) {
        g.save(); g.strokeStyle = sel ? "rgba(70,255,100,0.95)" : "rgba(255,60,50,0.95)"; g.lineWidth = 2.5;
        g.beginPath(); g.ellipse(G.x, G.y + 2, G.w * 0.5, G.w * 0.2, 0, 0, TAU); g.stroke(); g.restore();
      }
      imageMode(CORNER);
      image(G.img, G.x - G.w / 2, G.y - G.lift - G.h, G.w, G.h);
      if (sel || tgt) hpBar(G.x, G.y - G.lift - G.h - 10, Math.min(G.w * 0.8, 60), u.hp ? u.hp(t) : 1, sel ? [60, 230, 80] : [235, 60, 50]);
    }
  };

  const drawFog = (t, R, game, L, cam, top) => {
    const c = R.fog, W = L.W, H = L.H;
    if (c.width !== W || c.height !== H) { c.width = W; c.height = H; }
    const g = c.getContext("2d");
    g.globalCompositeOperation = "source-over";
    g.clearRect(0, 0, W, H);
    g.fillStyle = `rgba(0,0,0,${game.vision?.dark ?? 0.55})`; g.fillRect(0, top, W, H - top);
    g.globalCompositeOperation = "destination-out";
    const r = game.vision?.radius ?? 360;
    for (const u of game.units) {
      if (u.team !== "blue" || !Anim.rts.alive(u, t)) continue;
      const [x, y] = u.at(t), sx = x - cam[0], sy = y - cam[1] + top;
      const grad = g.createRadialGradient(sx, sy, 0, sx, sy, r);
      grad.addColorStop(0, "rgba(0,0,0,1)"); grad.addColorStop(0.62, "rgba(0,0,0,1)"); grad.addColorStop(1, "rgba(0,0,0,0)");
      g.fillStyle = grad; g.fillRect(sx - r, sy - r, 2 * r, 2 * r);
    }
    drawingContext.drawImage(c, 0, 0);
  };

  const dragBox = (t, game) => {
    const d = game.drag?.(t);
    if (!d) return;
    const [x0, y0] = d.a, [x1, y1] = d.b, g = drawingContext;
    g.save();
    g.fillStyle = "rgba(80,255,110,0.07)"; g.fillRect(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0));
    g.strokeStyle = "rgba(90,255,120,0.95)"; g.lineWidth = 2; g.strokeRect(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0));
    g.restore();
  };

  // ---- console screens --------------------------------------------------------------------------------------------

  const minimap = (t, R, game, r, cam, L) => {
    const g = drawingContext, ms = game.map.scale ?? 0.9;
    const mw = R.map.width * ms, mh = R.map.height * ms;
    const k = Math.min(r.w / mw, r.h / mh), ox = r.x + (r.w - mw * k) / 2, oy = r.y + (r.h - mh * k) / 2;
    g.save();
    g.fillStyle = "#000"; g.fillRect(r.x, r.y, r.w, r.h);
    g.globalAlpha = 0.85; imageMode(CORNER); image(R.map, ox, oy, mw * k, mh * k); g.globalAlpha = 1;
    // darkened unexplored edges
    g.fillStyle = "rgba(0,0,0,0.35)"; g.fillRect(ox, oy, mw * k * 0.18, mh * k); g.fillRect(ox + mw * k * 0.86, oy, mw * k * 0.14, mh * k);
    for (const u of game.units) {
      if (!Anim.rts.alive(u, t)) continue;
      const [x, y] = u.at(t);
      g.fillStyle = u.team === "blue" ? "#4aa0ff" : "#ff4a3a";
      g.fillRect(ox + x * k - 2, oy + y * k - 2, 4.5, 4.5);
    }
    // alerts: a ring that blinks where the fighting is
    for (const p of game.pings || []) {
      const age = t - p.at;
      if (age < 0 || age > 1.2) continue;
      const q = (age % 0.6) / 0.6;
      g.strokeStyle = `rgba(${p.color || "255,60,50"},${1 - q})`; g.lineWidth = 2;
      g.beginPath(); g.arc(ox + p.x * k, oy + p.y * k, 4 + 14 * q, 0, TAU); g.stroke();
    }
    // the camera box
    const vh = (L.top - (game.top ?? 44));
    g.strokeStyle = "rgba(255,255,255,0.95)"; g.lineWidth = 1.5;
    g.strokeRect(ox + cam[0] * k, oy + cam[1] * k, L.W * k, vh * k);
    g.restore();
  };

  const portraitScreen = (t, R, game, r, frame, mode) => {
    const g = drawingContext, img = R.portrait, pc = game.portrait || {};
    const cover = Math.max(r.w / img.width, r.h / img.height) * (1.04 + 0.012 * Math.sin(t * 0.9));
    const dw = img.width * cover, dh = img.height * cover;
    const ox = r.x + (r.w - dw) / 2 + 1.5 * Math.sin(t * 0.7), oy = r.y + (r.h - dh) / 2 + 2.2 * Math.sin(t * 1.6);
    const talking = (pc.talk || []).some(([a, b]) => t >= a && t < b);
    g.save();
    g.beginPath(); g.rect(r.x, r.y, r.w, r.h); g.clip();
    if (mode !== "light") {
      g.fillStyle = "#000"; g.fillRect(r.x, r.y, r.w, r.h);
      imageMode(CORNER); image(img, ox, oy, dw, dh);
      // monitor tint and scanlines inside the little screen
      g.fillStyle = "rgba(20,60,70,0.16)"; g.fillRect(r.x, r.y, r.w, r.h);
      g.fillStyle = "rgba(0,0,0,0.22)";
      for (let y = r.y + ((frame * 1.5) % 3); y < r.y + r.h; y += 3) g.fillRect(r.x, y, r.w, 1);
      if (talking) {
        for (let i = 0; i < 4; i++) {
          const v = P().rand("portrait-static", frame * 7 + i, 1);
          if (v < 0.45) continue;
          g.fillStyle = `rgba(200,255,240,${0.08 + 0.12 * P().rand("portrait-static", frame * 7 + i, 2)})`;
          g.fillRect(r.x, r.y + P().rand("portrait-static", frame * 7 + i, 3) * r.h, r.w, 2 + 6 * v);
        }
      }
    }
    // eyes: glow that pulses, brighter while it talks (in both layers, so the halo pass blooms them)
    const pulse = 0.55 + 0.25 * Math.sin(t * 5.2) + (talking ? 0.3 : 0);
    g.globalCompositeOperation = "lighter";
    for (const [ex, ey] of pc.eyes || []) P().glow(g, ox + ex * cover, oy + ey * cover, 16 * cover * 2.2, pc.eye || "#ffa040", pulse * (mode === "light" ? 0.8 : 0.5));
    g.restore();
  };

  const infoScreen = (t, R, game, r) => {
    const g = drawingContext;
    g.save();
    g.fillStyle = "#03070c"; g.fillRect(r.x, r.y, r.w, r.h);
    const sel = game.units.filter((u) => u.team === "blue" && Anim.rts.alive(u, t) && game.selected(t, u));
    const cols = 8, pad = 10, tw = (r.w - pad * 2) / cols - 6, th = Math.min(tw, (r.h - pad * 2) / 2 - 6);
    sel.slice(0, 16).forEach((u, i) => {
      const x = r.x + pad + (i % cols) * (tw + 6), y = r.y + pad + Math.floor(i / cols) * (th + 6);
      g.fillStyle = "#0b1622"; g.fillRect(x, y, tw, th);
      g.strokeStyle = "rgba(70,160,255,0.75)"; g.lineWidth = 1.5; g.strokeRect(x + 0.5, y + 0.5, tw - 1, th - 1);
      const face = game.iconOf?.(u);
      imageMode(CORNER);
      if (face) image(face, x + 2, y + 2, tw - 4, th - 14);
      else {
        const img = R.units[u.kind], k = Math.min((tw - 10) / img.width, (th - 18) / img.height);
        g.globalAlpha = 0.95; image(img, x + (tw - img.width * k) / 2, y + 4 + (th - 18 - img.height * k) / 2, img.width * k, img.height * k); g.globalAlpha = 1;
      }
      const hp = u.hp ? u.hp(t) : 1;
      g.fillStyle = hp > 0.6 ? "#3ee05a" : hp > 0.3 ? "#e8d040" : "#e84a3a";
      g.fillRect(x + 4, y + th - 10, (tw - 8) * hp, 5);
    });
    g.restore();
  };

  const gaugeScreen = (t, game, r) => {
    const g = drawingContext, v = clamp01(game.gauge ? game.gauge(t) : 0.7), n = 12;
    g.save();
    g.fillStyle = "#02060a"; g.fillRect(r.x, r.y, r.w, r.h);
    const sh = (r.h - 16) / n;
    for (let i = 0; i < n; i++) {
      const on = (i + 0.5) / n <= v, y = r.y + r.h - 8 - (i + 1) * sh;
      g.fillStyle = on ? `rgba(70,${170 + i * 6},255,${0.75 + 0.25 * Math.sin(t * 6 - i)})` : "rgba(30,50,70,0.6)";
      g.fillRect(r.x + 10, y + 2, r.w - 20, sh - 4);
    }
    g.restore();
  };

  const commandCard = (t, R, game, L, cur) => {
    const g = drawingContext;
    (game.commands || []).forEach((name, i) => {
      const r = L.sockets[i];
      if (!r || !R.icons[name]) return;
      const press = (game.pressed || []).find((p) => p.name === name && t >= p.at && t < p.at + 0.18);
      const hover = cur && cur.x >= r.x && cur.x < r.x + r.w && cur.y >= r.y && cur.y < r.y + r.h;
      const d = press ? 2 : 0;
      g.save();
      g.fillStyle = "#000"; g.fillRect(r.x, r.y, r.w, r.h);
      imageMode(CORNER); image(R.icons[name], r.x + 1 + d, r.y + 1 + d, r.w - 2 - d, r.h - 2 - d);
      if (hover) { g.globalCompositeOperation = "lighter"; g.fillStyle = "rgba(90,160,255,0.16)"; g.fillRect(r.x, r.y, r.w, r.h); }
      if (press) { g.globalCompositeOperation = "source-over"; g.fillStyle = "rgba(0,0,0,0.3)"; g.fillRect(r.x, r.y, r.w, r.h);
                   g.strokeStyle = "rgba(255,255,255,0.9)"; g.lineWidth = 2; g.strokeRect(r.x + 1, r.y + 1, r.w - 2, r.h - 2); }
      g.restore();
    });
  };

  // An original cursor: an angular green gauntlet-arrow, or a red reticle while an attack order waits for its target.
  const cursor = (c) => {
    if (!c) return;
    const g = drawingContext;
    g.save();
    g.translate(c.x, c.y);
    if (c.mode === "target") {
      g.strokeStyle = "rgba(255,70,50,0.95)"; g.lineWidth = 2.5; g.shadowColor = "rgba(255,40,30,0.9)"; g.shadowBlur = 8;
      g.beginPath(); g.arc(0, 0, 15, 0, TAU); g.stroke();
      g.beginPath();
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { g.moveTo(dx * 9, dy * 9); g.lineTo(dx * 23, dy * 23); }
      g.stroke();
      g.fillStyle = "#ffd0c0"; g.beginPath(); g.arc(0, 0, 2.2, 0, TAU); g.fill();
    } else {
      const s = c.down ? 0.92 : 1;
      g.scale(s, s);
      g.beginPath();
      g.moveTo(0, 0); g.lineTo(5, 33); g.lineTo(12, 25); g.lineTo(20, 38); g.lineTo(26, 35); g.lineTo(18, 22); g.lineTo(29, 19); g.closePath();
      const gr = g.createLinearGradient(0, 0, 24, 36); gr.addColorStop(0, "#d6ffcf"); gr.addColorStop(0.35, "#5ef25a"); gr.addColorStop(1, "#167a24");
      g.shadowColor = "rgba(80,255,90,0.75)"; g.shadowBlur = 10;
      g.fillStyle = gr; g.fill();
      g.shadowBlur = 0; g.strokeStyle = "#03200a"; g.lineWidth = 2; g.stroke();
      g.strokeStyle = "rgba(255,255,255,0.7)"; g.lineWidth = 1; g.beginPath(); g.moveTo(3, 5); g.lineTo(6, 26); g.stroke();
    }
    g.restore();
  };

  // Windows-classic title bar, like the other PC screens in the film.
  const titleBar = (game, W) => {
    const g = drawingContext, top = game.top ?? 44;
    const grad = g.createLinearGradient(0, 0, W, 0);
    grad.addColorStop(0, "#0a246a"); grad.addColorStop(1, "#a6caf0");
    g.save(); g.fillStyle = grad; g.fillRect(0, 0, W, top); g.restore();
    styledText(game.title, 28, 21, { font: game.fonts.uiBold, size: 28, style: "#ffffff", align: [LEFT, CENTER] });
    ["_", "o", "x"].forEach((c, i) => {
      const x = W - 118 + i * 36;
      noStroke(); fill("#d4d0c8"); rect(x, 8, 30, 28);
      stroke("#ffffff"); line(x, 8, x + 30, 8); line(x, 8, x, 36);
      stroke("#404040"); line(x, 36, x + 30, 36); line(x + 30, 8, x + 30, 36); noStroke();
      styledText(c, x + 15, 19, { font: game.fonts.uiBold, size: 20, style: "#000000" });
    });
  };

  // A warning across the battlefield, blinking, in the logo face: red letters on a dark band.
  const alertBanner = (t, game, L) => {
    const al = game.alert?.(t);
    if (!al || !(al.a > 0)) return;
    const f = game.fonts, g = drawingContext, y = (game.alertY ?? (L.top * 0.52));
    const blink = 0.72 + 0.28 * (Math.floor(t * 4) % 2 ? 1 : 0.35);
    g.save(); g.globalAlpha = al.a;
    const band = g.createLinearGradient(0, 0, L.W, 0);
    band.addColorStop(0, "rgba(40,0,0,0)"); band.addColorStop(0.25, "rgba(40,0,0,0.62)"); band.addColorStop(0.75, "rgba(40,0,0,0.62)"); band.addColorStop(1, "rgba(40,0,0,0)");
    g.fillStyle = band; g.fillRect(0, y - 44, L.W, al.sub ? 110 : 84);
    g.globalAlpha = al.a * blink;
    styledText(al.text, L.W / 2, y, { font: f.logo, size: 44, style: "#ff4a36", outline: "#1a0000", weight: 6, glow: "rgba(255,40,20,0.95)", blur: 22, spacing: 3 });
    if (al.sub) styledText(al.sub, L.W / 2, y + 44, { font: f.logo, size: 22, style: "#ffc8b8", glow: "rgba(255,60,40,0.7)", blur: 8, spacing: 4 });
    g.restore();
  };

  Anim.rts.ui = { bevelRect, styledText, logoPlate, cursor, hpBar, groundMarker, titleBar, resourceIcon };

  // ---- the whole screen -------------------------------------------------------------------------------------------

  Anim.rts.screen = (t, R, game, { mode = "color", frame = ANIM.frame } = {}) => {
    const L = Anim.rts.layout(R, game);
    const top = game.top ?? 44, cam = game.map.cam(t), ms = game.map.scale ?? 0.9;
    const ground = (game.events || []).filter((e) => e.type === "scorch");
    const air = (game.events || []).filter((e) => e.type !== "scorch");
    const g = drawingContext;
    const cur = game.cursor?.(t);

    if (mode === "light") {
      g.save(); g.beginPath(); g.rect(0, top, L.W, L.top - top + 200); g.clip();
      push(); translate(-cam[0], -cam[1] + top);
      P().draw(air, t, { mode: "light" });
      pop();
      g.restore();
      // Nothing shines through the console: cut its frame and its screens out of the light layer.
      g.save(); g.globalCompositeOperation = "destination-out";
      imageMode(CORNER); image(R.console, 0, L.y0, L.W, R.slots.h * L.k);
      g.fillStyle = "#000";
      for (const r of [...Object.values(L.screens), ...L.sockets]) g.fillRect(r.x, r.y, r.w, r.h);
      g.fillRect(0, 0, L.W, top + 80);
      g.restore();
      if (L.screens.portrait) portraitScreen(t, R, game, L.screens.portrait, frame, "light");
      return L;
    }

    background(0);
    g.save(); g.beginPath(); g.rect(0, top, L.W, L.H - top); g.clip();
    push(); translate(-cam[0], -cam[1] + top);
    g.filter = game.map.filter || "brightness(1.22) contrast(1.06) saturate(1.08)";
    imageMode(CORNER); image(R.map, 0, 0, R.map.width * ms, R.map.height * ms);
    g.filter = "none";
    P().draw(ground, t);
    for (const m of game.markers || []) groundMarker(t, m);
    drawUnits(t, R, game);
    pop();
    drawFog(t, R, game, L, cam, top);
    push(); translate(-cam[0], -cam[1] + top);
    P().draw(air, t);
    pop();
    g.restore();

    dragBox(t, game);
    alertBanner(t, game, L);
    topHud(t, game, L);

    const S = L.screens;
    if (S.minimap) minimap(t, R, game, S.minimap, cam, L);
    if (S.portrait) portraitScreen(t, R, game, S.portrait, frame, "color");
    if (S.info) infoScreen(t, R, game, S.info);
    if (S.gauge) gaugeScreen(t, game, S.gauge);
    commandCard(t, R, game, L, cur);
    imageMode(CORNER); image(R.console, 0, L.y0, L.W, R.slots.h * L.k);

    cursor(cur);
    titleBar(game, L.W);
    return L;
  };

  // World point -> screen point for the current camera (to aim the cursor at a unit).
  Anim.rts.toScreen = (game, t, [x, y]) => {
    const cam = game.map.cam(t);
    return [x - cam[0], y - cam[1] + (game.top ?? 44)];
  };
})();
