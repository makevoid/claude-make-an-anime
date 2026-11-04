// EMBER × TEMPEST: the title card, the layered composite and the subtitles. Times are scene seconds.
const HIT = 5.6;    // the first clash
const FIRE = [255, 150, 60], STORM = [130, 190, 255];

Anim.sketch({
  async load() {
    this.f = await Anim.fonts({ title: "title.ttf", sub: "sub.ttf", subItalic: "sub-italic.ttf" });
    this.kaen = await Anim.clip("kaen");
    this.arashi = await Anim.clip("arashi");
    this.lines = Anim.data("dialogue");
    this.shots = Anim.data("shots");
  },

  draw(t, frame) {
    const shot = Anim.shotAt(frame, this.shots);
    if (shot.name === "title") this.title(t, frame);
    if (shot.name === "composite-plate") this.composite(t, frame);
    if (shot.name !== "title") Anim.subtitles(t, this.lines, { font: this.f.sub, italic: this.f.subItalic, size: 50 });
    // Smash whites around the cuts.
    Anim.flash(Anim.tween(t, 1.88, 0.12, 0, 1, Anim.ease.inCubic) - Anim.tween(t, 2.0, 0.25, 0, 1));
    Anim.flash(Anim.tween(t, 6.85, 0.15, 0, 1, Anim.ease.inCubic) - Anim.tween(t, 7.0, 0.3, 0, 1));
  },

  title(t, frame) {
    const g = drawingContext;
    // Two lights fight across the card: fire from the left, storm from the right.
    const glow = (x, c, a) => {
      const r = g.createRadialGradient(x, height / 2, 0, x, height / 2, 1000);
      r.addColorStop(0, `rgba(${c},${a})`); r.addColorStop(1, `rgba(${c},0)`);
      g.fillStyle = r; g.fillRect(0, 0, width, height);
    };
    const open = Anim.tween(t, 0.1, 0.3, 0.2, 0.75);
    glow(160, FIRE.join(","), open);
    glow(width - 160, STORM.join(","), open * 0.9);
    Anim.speedLines(frame, width / 2, height * 0.47, { count: 46, inner: 620, alpha: 0.28 * Anim.tween(t, 0.1, 0.2, 0, 1), seed: 5 });
    Anim.embers(t, { count: 50, depth: 1.2, color: FIRE, wind: [120, -160] });
    Anim.embers(t, { count: 30, depth: 0.8, seed: 9, color: STORM, wind: [-120, -80] });
    Anim.titleSlam(t, { title: "EMBER × TEMPEST", tagline: "EPISODE 0  ·  THE FIRST CLASH", font: this.f.title, tagFont: this.f.sub, size: 190 });
  },

  // Keyed fighters over the animated plate. They circle a shared centre, stay apart, rush in so the fist meets the open
  // hand for the hit and recoil, all inside the same roll as the plate, so sprites and background turn as one camera.
  composite(t, frame) {
    const after = t - HIT;
    const dash = Anim.progress(t, HIT - 0.5, 0.5, Anim.ease.inCubic);
    const reach = t < HIT ? 610 - 40 * Anim.progress(t, 2, HIT - 2.5, Anim.ease.inOutCubic) - 110 * dash
                          : 460 + 120 * Anim.ease.outCubic(Anim.clamp01(after / 0.45));
    const angle = Anim.tween(t, 2, 5, -0.22, 0.3, Anim.ease.inOutCubic);
    const cx = width / 2, cy = height * 0.55;
    const shake = t >= HIT ? Anim.shake(t, HIT, { dur: 0.55, amp: 30 }) : { x: 0, y: 0 };
    const depth = Math.sin(angle * 3);
    const place = (who, side) => ({
      who, side, x: cx + side * reach * Math.cos(angle) + shake.x, y: cy + side * reach * Math.sin(angle) * 0.5 + shake.y,
      h: 730 * (1 + side * depth * 0.07),
    });
    const fighters = [place(this.kaen, -1), place(this.arashi, 1)].sort((a, b) => a.h - b.h);

    Anim.withRoll(frame, () => {
      Anim.embers(t, { count: 30, depth: 0.7, seed: 21, color: FIRE, wind: [-200, -60], size: 3 });
      const lines = t < HIT ? dash : 1 - Anim.clamp01(after / 0.9);
      if (lines > 0) Anim.speedLines(frame, cx, cy, { count: 80, inner: 420, alpha: 0.6 * lines });
      for (const f of fighters) {
        const [r, gr, b] = f.side < 0 ? FIRE : STORM;
        Anim.aura(`rgba(${r},${gr},${b},0.8)`, 26, () => f.who.draw(f.who.at(t), f.x, f.y, f.h));
      }
      Anim.impactBloom(cx, cy, after / 0.75, { radius: 900 });
      Anim.shockRing(cx, cy, after / 0.9, { radius: 1250, weight: 30 });
      Anim.shockRing(cx, cy, (after - 0.08) / 1.1, { radius: 1500, color: STORM, weight: 18 });
      Anim.embers(t, { count: 16, depth: 1.8, seed: 33, color: [255, 220, 170], wind: [-260, -100], size: 2.2 });
    }, this.shots);
    if (after >= 0 && after < 0.1) Anim.flash(0.85);
    Anim.vignette(0.45);
  },
});
