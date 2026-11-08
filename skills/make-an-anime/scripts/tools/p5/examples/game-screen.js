// Supply --data game=recipe.json where recipe has {dir, units:[...], icons:[...]}.
// Art is produced with the game-screens guide; no generated media is bundled.
Anim.sketch({
  async load() {
    const config = Anim.data('game');
    this.art = await Anim.rts.load(config);
    const kind = config.units[0];
    this.game = {
      title: 'Orbital Command', logo: { text: 'ORBITAL', sub: 'COMMAND' },
      fonts: { ui: 'sans-serif', uiBold: 'sans-serif', logo: 'sans-serif' },
      map: { scale: 1, cam: t => [20 * t, 0] },
      kinds: { [kind]: { w: 70 } },
      units: [{ id: 'scout', kind, team: 'blue', at: t => [400 + 45 * t, 300] }],
      selected: () => true,
      events: [{ type: 'laser', id: 'shot', at: 0.3, dur: 0.3, from: [430, 265], to: [680, 250] }],
      timer: t => `00:${String(Math.floor(t)).padStart(2, '0')}`,
      resources: () => [{ icon: 'crystal', text: '120' }],
      commands: config.icons || [], gauge: () => 0.7,
      cursor: t => ({ x: 650 + 20 * t, y: 300, mode: 'target' })
    };
  },
  draw(t, frame) {
    Anim.rts.screen(t, this.art, this.game, { frame, mode: ANIM.data.vfx !== undefined ? 'light' : 'color' });
  }
});
