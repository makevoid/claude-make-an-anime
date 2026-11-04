// Battle: title drops, speed lines, impacts and the virtual camera roll for layered action scenes. Everything is seeded
// or a pure function of time, so a frame renders the same way every time.
//
//   Anim.titleSlam(local, { title: "EMBER × TEMPEST", tagline: "...", font, tagFont });
//   Anim.withRoll(frame, () => sprite.draw(...));   // same roll as the shot's `roll: [from, to]` plate
//   Anim.aura("#ff6a1f", 40, () => sprite.draw(...));
window.Anim = window.Anim || {};

(() => {
  // The shot under `frame` from Anim.data("shots"): { name, start_frame, frames, roll, local (seconds), p (0..1) }.
  Anim.shotAt = (frame, shots = Anim.data("shots")) => {
    const s = shots.find((x) => frame >= x.start_frame && frame < x.start_frame + x.frames);
    if (!s) return null;
    return { ...s, local: (frame - s.start_frame) / ANIM.fps, p: (frame - s.start_frame) / Math.max(s.frames - 1, 1) };
  };

  // The eased plate roll at `frame`, in degrees: must match Media::FFmpeg#roll_filter.
  Anim.rollAt = (frame, shots) => {
    const s = Anim.shotAt(frame, shots);
    if (!s?.roll) return 0;
    return s.roll[0] + (s.roll[1] - s.roll[0]) * (3 * s.p ** 2 - 2 * s.p ** 3);
  };

  // Draw fn in the camera's frame, turning with the plate around the middle of the canvas.
  Anim.withRoll = (frame, fn, shots) => {
    push();
    translate(width / 2, height / 2);
    rotate((Anim.rollAt(frame, shots) * Math.PI) / 180);
    translate(-width / 2, -height / 2);
    fn();
    pop();
  };

  // A glow that follows the alpha of whatever fn draws (a sprite's silhouette).
  Anim.aura = (color, blur, fn) => {
    const g = drawingContext;
    const prev = [g.shadowColor, g.shadowBlur];
    g.shadowColor = color; g.shadowBlur = blur;
    fn();
    [g.shadowColor, g.shadowBlur] = prev;
  };

  // Radial speed lines around (cx, cy), a new seed each `hold` frames so they flicker like hand-drawn ones.
  Anim.speedLines = (frame, cx, cy, { count = 70, inner = 340, outer = 1500, color = [255, 255, 255], alpha = 0.55, weight = 7, hold = 2, seed = 11 } = {}) => {
    const rng = Anim.rng(seed + Math.floor(frame / hold) * 97);
    const g = drawingContext;
    g.save();
    for (let i = 0; i < count; i++) {
      const a = rng() * Math.PI * 2, r0 = inner * (0.7 + rng() * 0.8), r1 = outer * (0.7 + rng() * 0.3), w = weight * (0.25 + rng());
      const c = Math.cos(a), s = Math.sin(a), nx = -s * w, ny = c * w;
      g.fillStyle = `rgba(${color[0]},${color[1]},${color[2]},${alpha * (0.35 + rng() * 0.65)})`;
      g.beginPath();
      g.moveTo(cx + c * r0, cy + s * r0);
      g.lineTo(cx + c * r1 + nx, cy + s * r1 + ny);
      g.lineTo(cx + c * r1 - nx, cy + s * r1 - ny);
      g.closePath();
      g.fill();
    }
    g.restore();
  };

  // An expanding shock ring: `p` 0..1 from the hit.
  Anim.shockRing = (x, y, p, { radius = 900, color = [255, 240, 210], weight = 44 } = {}) => {
    if (p <= 0 || p >= 1) return;
    const k = Anim.ease.outCubic(p);
    const g = drawingContext;
    g.save();
    g.strokeStyle = `rgba(${color[0]},${color[1]},${color[2]},${(1 - p) * 0.9})`;
    g.lineWidth = weight * (1 - p) + 1;
    g.shadowColor = `rgb(${color[0]},${color[1]},${color[2]})`; g.shadowBlur = 40;
    g.beginPath(); g.ellipse(x, y, radius * k, radius * k * 0.72, -0.2, 0, Math.PI * 2); g.stroke();
    g.restore();
  };

  // A hot centre that blooms and dies at a hit.
  Anim.impactBloom = (x, y, p, { radius = 520, core = "255,255,255", edge = "255,160,70" } = {}) => {
    if (p <= 0 || p >= 1) return;
    const g = drawingContext, a = 1 - p, r = radius * Anim.ease.outExpo(p);
    const grad = g.createRadialGradient(x, y, 0, x, y, r);
    grad.addColorStop(0, `rgba(${core},${a})`);
    grad.addColorStop(0.35, `rgba(${edge},${a * 0.7})`);
    grad.addColorStop(1, `rgba(${edge},0)`);
    g.fillStyle = grad;
    g.fillRect(x - r, y - r, r * 2, r * 2);
  };

  // Drifting sparks. `depth` scales speed and size, so a near layer passes faster than a far one.
  Anim.embers = (t, { count = 60, seed = 3, color = [255, 170, 80], depth = 1, wind = [-60, -120], size = 5 } = {}) => {
    const rng = Anim.rng(seed);
    const g = drawingContext;
    g.save();
    for (let i = 0; i < count; i++) {
      const x0 = rng() * width, y0 = rng() * height, phase = rng() * 6.28, s = (0.4 + rng()) * size * depth, speed = 0.6 + rng() * 0.8;
      const x = (((x0 + wind[0] * depth * speed * t + Math.sin(t * 2 + phase) * 18) % width) + width) % width;
      const y = (((y0 + wind[1] * depth * speed * t) % height) + height) % height;
      g.fillStyle = `rgba(${color[0]},${color[1]},${color[2]},${0.45 + 0.45 * Math.sin(t * 5 + phase) ** 2})`;
      g.shadowColor = `rgb(${color[0]},${color[1]},${color[2]})`; g.shadowBlur = 10;
      g.beginPath(); g.arc(x, y, s, 0, Math.PI * 2); g.fill();
    }
    g.restore();
  };

  // A full-frame colour: smash whites and fades.
  Anim.flash = (alpha, color = "255,255,255") => {
    if (alpha <= 0) return;
    drawingContext.fillStyle = `rgba(${color},${Math.min(alpha, 1)})`;
    drawingContext.fillRect(0, 0, width, height);
  };

  // Title drop: the title slams in oversized, the frame shakes, a tagline follows. `local`: seconds into the card.
  Anim.titleSlam = (local, { title, tagline = "", font, tagFont = font, size = 170, color = "#fff4e0", glow = "#ff6a1f", tagColor = "#ffd9a8", at = 0.1, tagAt = 0.75, y = height * 0.47, spacing = 8 } = {}) => {
    const slam = Anim.slam(local, at, { dur: 0.14, from: 2.1 });
    const shake = Anim.shake(local, at + 0.14, { dur: 0.4, amp: 18 });
    const g = drawingContext;
    Anim.at(width / 2 + shake.x, y + shake.y, slam, () => {
      textFont(font); textSize(size); textAlign(CENTER, CENTER);
      g.letterSpacing = `${spacing}px`;
      g.shadowColor = glow; g.shadowBlur = 46;
      fill(color); noStroke();
      text(title, 0, 0);
      g.shadowBlur = 0;
      g.letterSpacing = "0px";
    });
    if (tagline) {
      const a = Anim.tween(local, tagAt, 0.25, 0, 1);
      textFont(tagFont); textSize(size * 0.2); textAlign(CENTER, CENTER);
      g.letterSpacing = `${size * 0.05}px`;
            g.globalAlpha = a; fill(tagColor); text(tagline, width / 2, y + size * 0.82); g.globalAlpha = 1;
      g.letterSpacing = "0px";
    }
  };
})();
