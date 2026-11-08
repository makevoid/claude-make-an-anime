// One Round at the River: the opening manga page, the finishing flash and the subtitles. Times are scene seconds.
const KO = 10.083, PAGE_END = 5, END = 410 / 24;
const CUT = [1040, 880]; // the paper cut's x at the top and bottom of the frame
const LEFT_X = 470, RIGHT_X = 1450; // subtitle centres under each panel

Anim.sketch({
  async load() {
    this.f = await Anim.fonts({ sub: "sub.ttf" });
    this.riku = await Anim.clip("panel-riku");
    this.ren = await Anim.clip("panel-ren");
    this.lines = Anim.data("dialogue").filter((l) => l.name !== "ren-kiai");
  },

  draw(t) {
    if (t < PAGE_END) {
      // One slow push on each whole painted panel, so character and world move as one camera.
      const s = 1.14 + 0.03 * (t / PAGE_END);
      Anim.paperCutPanels(
        () => this.riku.draw(this.riku.at(t), width * 0.5 * s - 150, height * 0.5 * s, height * s),
        () => this.ren.draw(this.ren.at(t), width - width * 0.5 * s + 190, height * 0.5 * s, height * s),
        { cut: CUT, gutter: 26 }
      );
    }
    if (t >= KO && t < KO + 0.05) Anim.flash(0.9);
    Anim.vignette(0.22);
    if (t < PAGE_END) {
      const sub = { font: this.f.sub, italic: this.f.sub, size: 44, tail: 0.1 };
      Anim.subtitles(t, this.lines, { ...sub, x: LEFT_X, skip: (l) => l.character !== "riku" });
      Anim.subtitles(t, this.lines, { ...sub, x: RIGHT_X, skip: (l) => l.character !== "ren" });
    } else {
      Anim.subtitles(t, this.lines, { font: this.f.sub, italic: this.f.sub, size: 46, tail: 0.1 });
    }
    Anim.flash(1 - Anim.clamp01(t / 0.3), "0,0,0");
    Anim.flash(Anim.clamp01((t - (END - 0.5)) / 0.5), "0,0,0");
  },
});
