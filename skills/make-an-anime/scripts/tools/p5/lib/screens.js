// Screens: the readable parts of an anime scene that p5 draws over the H3 plate — code editors and terminals on a
// monitor insert, typing, subtitles, the monitor vignette. Generated images never contain text; everything readable
// comes from here.
//
//   const typing = Anim.typing("life = Life.new(1987)", { seed: 1987 });     // deterministic key times (s)
//   Anim.codeEditor(local, dur, { font, tokens: [["life", "#e6edf7"], [" = ", "#ff79c6"], ...], typing, zoom: [1.1, 1.16] });
//   Anim.subtitles(t, Anim.data("dialogue"), { font, italic });
//   Anim.vignette(0.6);
//
// Pitfalls these helpers avoid:
// - p5's textWidth() ignores leading/trailing spaces with a loaded font: code is laid out on a monospace grid instead.
// - A canvas radial gradient leaves the inside of a non-zero inner radius unpainted, and interpolates colours
//   unpremultiplied (a tinted stop next to a black stop paints a bright ring): the vignette is black-only, alpha-only.
window.Anim = window.Anim || {};

(() => {
  // Monospace grid for a loaded font: one advance per glyph, so spaces count.
  Anim.mono = (font, size) => {
    textFont(font);
    textSize(size);
    const adv = textWidth("0");
    return {
      adv,
      size,
      // Draw coloured tokens [[str, colour], ...] from x, y (baseline); only the first `limit` glyphs. Returns glyphs drawn.
      tokens(tokens, x, y, limit = Infinity) {
        textFont(font); textSize(size); textAlign(LEFT, BASELINE);
        let col = 0;
        for (const [str, colour] of tokens) {
          for (const ch of str) {
            if (col >= limit) return col;
            if (ch !== " ") { fill(colour); text(ch, x + col * adv, y); }
            col++;
          }
        }
        return col;
      },
    };
  };

  // Deterministic typing rhythm: a key time per character plus an optional Enter, in seconds from `start`.
  // { chars: [t0, t1, ...], enter, count(t), last(t) } — use the same times for keyboard SFX cues.
  Anim.typing = (str, { seed = 1, start = 0.08, base = 0.038, jitter = 0.03, spacePause = 0.03, enterPause = 0.14, enter = true } = {}) => {
    const rng = Anim.rng(seed);
    const chars = [];
    let t = start;
    for (const ch of str) { chars.push(t); t += base + rng() * jitter + (ch === " " ? spacePause : 0); }
    const enterAt = enter ? t + enterPause : null;
    return {
      text: str,
      chars,
      enter: enterAt,
      count: (now) => chars.filter((c) => now >= c).length,
      entered: (now) => enterAt !== null && now >= enterAt,
      last: (now) => Math.max(-9, ...chars.filter((c) => now >= c), enterAt !== null && now >= enterAt ? enterAt : -9),
    };
  };

  // Cursor visibility: solid for `hold` s after the last key, then blinking at `hz`.
  Anim.cursorOn = (now, lastKey = -9, { hold = 0.4, hz = 1.9 } = {}) => now - lastKey <= hold || Math.floor(now * hz * 2) % 2 === 0;

  Anim.EDITOR_DARK = { bg: "#0b0f17", panel: "#0f1522", bar: "#141c2b", gutter: "#3a4660", text: "#e6edf7", dim: "#6b7894", cursor: "#7fd8ff", glow: "#7fd8ff" };

  // Full-screen code editor on a monitor insert. `local`/`dur`: seconds into / length of the insert.
  //   font, size 64, tokens (the line being typed), typing (Anim.typing result; omit for an empty file with a blinking
  //   cursor), above: earlier lines as token arrays, filename "main.rb", lang "Ruby", colors (EDITOR_DARK),
  //   zoom [from, to] eased push toward the cursor (empty file) or the middle of the line (typing), vignette 0.6,
  //   scanlines true, flash: brighten toward white after Enter (leads into a smash cut).
  Anim.codeEditor = (local, dur, { font, size = 64, tokens = [], typing = null, above = [], filename = "main.rb", lang = "",
                                   colors = Anim.EDITOR_DARK, zoom = [1, 1], vignette = 0.6, scanlines = true, flash = 0 } = {}) => {
    const C = colors, W = width, H = height;
    const grid = Anim.mono(font, size);
    const lh = size * 1.6;
    const lineText = tokens.map((p) => p[0]).join("");
    const cols = Math.max(lineText.length, ...above.map((l) => l.map((p) => p[0]).join("").length), 12);
    const x0 = Math.round((W - cols * grid.adv) / 2 + grid.adv * 1.5);
    const y0 = Math.round(H * 0.47 - (above.length * lh) / 2) + above.length * lh;
    const typed = typing ? typing.count(local) : 0;
    const entered = typing ? typing.entered(local) : false;
    const cx = entered ? x0 : x0 + typed * grid.adv, cy = entered ? y0 + lh : y0;
    const fx = typing ? x0 + (lineText.length * grid.adv) / 2 : cx, fy = y0 - size * 0.35;
    const k = Anim.tween(local, 0, dur, zoom[0], zoom[1], Anim.ease.inOutCubic);

    push();
    background(C.bg);
    translate(fx, fy); scale(k); translate(-fx, -fy);
    noStroke();
    fill(C.panel); rect(120, 120, W - 240, H - 240, 18);
    fill(C.bar); rect(120, 120, W - 240, 72, 18, 18, 0, 0);
    [["#ff5f57", 0], ["#febc2e", 1], ["#28c840", 2]].forEach(([c, i]) => { fill(c); circle(164 + i * 36, 156, 20); });
    textFont(font); textSize(28);
    const tabW = textWidth(filename) + 64;
    fill(C.panel); rect(260, 134, tabW, 58, 10, 10, 0, 0);
    fill(C.text); textAlign(LEFT, CENTER); text(filename, 292, 162);
    if (lang) { fill(C.dim); textAlign(RIGHT, CENTER); text(lang, W - 160, H - 150); }

    const first = y0 - above.length * lh;
    const nLines = above.length + 1 + (entered ? 1 : 0);
    textSize(size); textAlign(RIGHT, BASELINE);
    for (let i = 0; i < nLines; i++) { fill(i === nLines - 1 ? C.dim : C.gutter); text(String(i + 1), x0 - grid.adv * 2, first + i * lh); }
    fill(255, 255, 255, 10); rect(120, cy - size * 1.05, W - 240, lh);
    above.forEach((line, i) => grid.tokens(line, x0, first + i * lh));
    grid.tokens(tokens, x0, y0, typed);

    if (Anim.cursorOn(local, typing ? typing.last(local) : -9)) {
      drawingContext.shadowBlur = 28; drawingContext.shadowColor = C.glow;
      fill(C.cursor); rect(cx + 2, cy - size * 0.82, 6, size, 1);
      drawingContext.shadowBlur = 0;
    }
    pop();

    if (vignette) Anim.vignette(vignette);
    if (scanlines) Anim.scanlines();
    if (flash && entered) {
      drawingContext.fillStyle = `rgba(255,255,255,${Anim.tween(local, typing.enter, dur - typing.enter, 0, flash, (x) => x * x)})`;
      drawingContext.fillRect(0, 0, W, H);
    }
    return { cursor: [cx, cy], typed, entered };
  };

  // Darkened edges: black only, alpha only, inner radius 0 (see the pitfalls above).
  Anim.vignette = (strength = 0.6, { inner = 0.45 } = {}) => {
    const g = drawingContext, W = width, H = height;
    const grad = g.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, H * 0.95);
    grad.addColorStop(0, "rgba(0,0,0,0)");
    grad.addColorStop(inner, `rgba(0,0,0,${(strength * 0.13).toFixed(3)})`);
    grad.addColorStop(1, `rgba(0,0,0,${strength})`);
    g.fillStyle = grad;
    g.fillRect(0, 0, W, H);
  };

  Anim.scanlines = (alpha = 0.07, step = 4) => {
    drawingContext.fillStyle = `rgba(0,0,0,${alpha})`;
    for (let y = 0; y < height; y += step) drawingContext.fillRect(0, y, width, 1);
  };

  // Subtitles from Anim.data("dialogue") lines ({ text, at, end, vo }): one at a time, lower third, white with a soft
  // shadow, narration in `italic`. Performed audio tags ([whispering]) are removed.
  // Lines start where the voice actually starts: `speech_at` is measured from each take's leading silence by the Dialogue
  // step (a take with a muted stumble at its head would otherwise show the subtitle early). Word-alignment times are
  // not used for this: after a long performance tag they placed a line's first word 1.1 s after the voice began.
  Anim.spoken = (lines) => lines.map((l) => (l.speech_at != null ? { ...l, at: Math.max(l.at, l.speech_at) } : l));
  const spokenCache = new WeakMap();

  Anim.subtitles = (t, lines, { font, italic = font, size = 46, y = height - 92, lead = 0.05, tail = 0.35, skip = () => false } = {}) => {
    if (!spokenCache.has(lines)) spokenCache.set(lines, Anim.spoken(lines));
    const l = spokenCache.get(lines).find((x) => t >= x.at - lead && t < x.end + tail && !skip(x));
    if (!l) return null;
    const str = (l.subtitle || l.text).replace(/\[[^\]]*\]\s*/g, "").trim();
    const a = Anim.envelope(t, l.at - lead, l.end + tail, 0.12, 0.2);
    textFont(l.vo ? italic : font); textSize(size); textAlign(CENTER, BASELINE);
    drawingContext.shadowBlur = 14; drawingContext.shadowColor = `rgba(0,0,0,${0.9 * a})`;
    fill(0, 0, 0, 150 * a); text(str, width / 2 + 2, y + 2);
    fill(255, 255, 255, 255 * a); text(str, width / 2, y);
    drawingContext.shadowBlur = 0;
    return l;
  };

  // Place/date card ("CITY · 1999"): letter-spaced, fading in.
  Anim.placeCard = (local, str, { font, size = 64, color = [40, 44, 52], alpha = 0.75, at = 0.05, fade = 0.3, spacing = 18, y = height / 2 } = {}) => {
    const a = Anim.tween(local, at, fade, 0, alpha);
    textFont(font); textSize(size); textAlign(CENTER, CENTER);
    fill(...color, 255 * a);
    drawingContext.letterSpacing = `${spacing}px`;
    text(str, width / 2, y);
    drawingContext.letterSpacing = "0px";
  };
})();
