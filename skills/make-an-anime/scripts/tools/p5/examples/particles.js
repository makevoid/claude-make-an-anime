// Render through anim:render. The same sketch supplies its own VFX light layer.
Anim.sketch({
  draw(t) {
    const light = ANIM.data.vfx !== undefined;
    if (!light) background('#102030');
    const events = [
      { type: 'laser', id: 'beam', at: 0.1, dur: 0.5, from: [40, 130], to: [230, 80] },
      { type: 'explosion', id: 'hit', at: 0.4, x: 230, y: 80, size: 0.45 },
      { type: 'sparks', id: 'sparks', at: 0.4, x: 230, y: 80, count: 12, speed: [30, 100], gravity: 70 },
      { type: 'scorch', id: 'mark', at: 0.4, x: 230, y: 80, radius: 15 }
    ];
    Anim.particles.draw(events, t, { mode: light ? 'light' : 'color' });
  }
});
