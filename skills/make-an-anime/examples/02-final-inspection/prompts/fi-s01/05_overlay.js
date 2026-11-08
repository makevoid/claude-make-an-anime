// Final Inspection (2.6): subtitles, the title and the fades, plus the eye light in the last shot. H3 turned a lit lens into
// a searchlight, so that shot is animated with a plain lens and the small amber point is drawn here, on the locked camera.
const END = 816 / 24, TITLE = 29.9, LAST_SHOT = 708 / 24;
const EYE = { x: 353, y: 286 };
const MINCHO = "Hiragino Mincho ProN";

function eyeLight(t) {
  const a = 0.92 + 0.08 * Math.sin(t * 2.1);
  const ctx = drawingContext;
  const glow = ctx.createRadialGradient(EYE.x, EYE.y, 0, EYE.x, EYE.y, 15);
  glow.addColorStop(0, `rgba(255,176,84,${0.75 * a})`);
  glow.addColorStop(0.35, `rgba(240,140,60,${0.28 * a})`);
  glow.addColorStop(1, "rgba(240,140,60,0)");
  ctx.fillStyle = glow;
  ctx.beginPath(); ctx.arc(EYE.x, EYE.y, 15, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = `rgba(255,226,170,${a})`;
  ctx.beginPath(); ctx.arc(EYE.x, EYE.y, 2.4, 0, Math.PI * 2); ctx.fill();
}

Anim.sketch({
  async load() {
    this.f = await Anim.fonts({ sub: "sub.ttf" });
    this.lines = Anim.data("dialogue");
  },

  draw(t) {
    if (t >= LAST_SHOT) eyeLight(t);
    Anim.vignette(0.2);
    Anim.subtitles(t, this.lines, { font: this.f.sub, italic: this.f.sub, size: 42, tail: 0.15 });

    if (t >= TITLE) {
      const a = Anim.envelope(t, TITLE + 0.2, END - 0.5, 0.8, 0.6);
      textFont(MINCHO); textAlign(CENTER, CENTER); noStroke();
      fill(30, 40, 54, 245 * a); textSize(92); text("最終点検", width / 2, height * 0.66);
      fill(30, 40, 54, 225 * a); textSize(34); text("Final Inspection", width / 2, height * 0.66 + 82);
    }
    Anim.flash(1 - Anim.clamp01(t / 0.9), "0,0,0");
    if (t >= END - 0.6) Anim.flash(Anim.clamp01((t - (END - 0.6)) / 0.6), "0,0,0");
  },
});
