// Sample Seven: subtitles, one white smash on the fast cut, the title and the fades. Times are scene seconds.
// Draw only what is not in the painting: text, cuts, light. More: 03-riverbank-bout (paper-cut panels drawn here),
// 02-final-inspection (a small light drawn on a locked shot), 04-too-salty (text cards, subtitle timing by hand).
const DASH = 192 / 24, TITLE = 300 / 24, END = 336 / 24;

Anim.sketch({
  async load() {
    this.f = await Anim.fonts({ sub: "sub.ttf" });
    this.lines = Anim.data("dialogue");
  },

  draw(t) {
    Anim.vignette(0.2);
    Anim.subtitles(t, this.lines, { font: this.f.sub, italic: this.f.sub, size: 44, tail: 0.15 });
    // The only shounen beat: a white smash into the run.
    Anim.flash(Anim.tween(t, DASH - 0.1, 0.1, 0, 0.8, Anim.ease.inCubic) - Anim.tween(t, DASH, 0.2, 0, 0.8));
    if (t >= TITLE) {
      const a = Anim.envelope(t, TITLE + 0.1, END - 0.1, 0.4, 0.4);
      textFont(this.f.sub); textSize(84); textAlign(CENTER, CENTER); noStroke();
      fill(240, 235, 222, 255 * a); text("SAMPLE SEVEN", width / 2, height / 2);
    }
    Anim.flash(1 - Anim.clamp01(t / 0.6), "0,0,0");
  },
});
