// A cut-out prop moving over transparency using the existing animation timeline.
// --data assets=config/assets.json: {"sprite":"/output/art/leaf.png"}
Anim.sketch({
  async load() {
    this.sprite = await loadImage(Anim.data('assets').sprite);
  },
  draw(t) {
    const q = Anim.progress(t, 0, 2, Anim.ease.inOutCubic);
    const h = height * 0.3;
    translate(width * (0.2 + 0.6 * q), height * (0.5 - 0.15 * Math.sin(Math.PI * q)));
    rotate(0.4 * Math.sin(Math.PI * q));
    imageMode(CENTER);
    image(this.sprite, 0, 0, h * this.sprite.width / this.sprite.height, h);
  }
});
