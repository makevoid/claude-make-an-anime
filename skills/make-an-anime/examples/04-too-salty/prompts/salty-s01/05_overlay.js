// Too Salty: subtitles, the two cards, the title and the fades. Nothing here sits on top of the painting except readable text.
const END = 1764 / 24, TITLE = 70.708, TRAY = 12.5, TRAY_END = 16.5;
const MINCHO = "Hiragino Mincho ProN";

// A small text card in the film's quiet serif, lower left, fading in and out.
const card = (t, from, to, str, size = 40) => {
  const a = Anim.envelope(t, from, to, 0.4, 0.5);
  if (a <= 0) return;
  textFont(MINCHO); textSize(size); textAlign(LEFT, BASELINE);
  drawingContext.shadowBlur = 12; drawingContext.shadowColor = `rgba(0,0,0,${0.85 * a})`;
  fill(245, 240, 228, 235 * a); text(str, 96, 120);
  drawingContext.shadowBlur = 0;
};

// Each subtitle starts on the voice, and gives way when the next line starts. These three takes say the word twice and
// the mix mutes the first, so the voice lands later than the gate alone says (measured on 03_dialogue.wav).
const LANDS = { "kiku-salty1": 10.9, "kiku-salty2": 17.69, "kiku-salty3": 55.6 };
const TAIL = 0.15;
const timed = (lines) => lines.map((l) => ({ ...l, speech_at: LANDS[l.name] ?? l.speech_at })).map((l, i, all) => {
  const next = all[i + 1];
  return next ? { ...l, end: Math.min(l.end, Math.max(next.at, next.speech_at ?? 0) - TAIL - 0.05) } : l;
});

Anim.sketch({
  async load() {
    this.f = await Anim.fonts({ sub: "sub.ttf" });
    this.lines = timed(Anim.data("dialogue"));
  },

  draw(t) {
    Anim.vignette(0.2);
    card(t, 0.4, 2.8, "午前5時");
    card(t, TRAY + 0.3, TRAY_END - 0.2, "DAY 91");
    Anim.subtitles(t, this.lines, { font: this.f.sub, italic: this.f.sub, size: 42, tail: TAIL });

    if (t >= TITLE) {
      const a = Anim.envelope(t, TITLE + 0.3, END - 0.1, 0.7, 0.5);
      textFont(MINCHO); textSize(96); textAlign(CENTER, CENTER);
      fill(240, 235, 222, 255 * a); text("しょっぱい", width / 2, height / 2);
    }
    Anim.flash(1 - Anim.clamp01(t / 0.6), "0,0,0");
    if (t >= TITLE - 0.5 && t < TITLE) Anim.flash(Anim.clamp01((t - (TITLE - 0.5)) / 0.5), "0,0,0");
  },
});
