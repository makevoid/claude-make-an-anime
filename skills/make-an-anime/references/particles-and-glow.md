# Particles and light-only glow

`Anim.particles` draws deterministic emitters in p5. It is loaded by the renderer after `battle`. Use it for screen content, sparks or an effect that belongs to the approved art direction; it does not replace a body's physical contact with its scene.

Every event has a unique `id`, a start time `at` in seconds, and coordinates in the current canvas transform. `Anim.particles.draw(events, t, {mode: 'color'})` draws the full event; `mode: 'light'` draws only luminous parts. Use shot-local seconds for both event times and `t`.

| Type | Main options |
| --- | --- |
| `sparks` | `x, y`, `count`, `speed: [min,max]`, `life: [min,max]`, `angle`, `spread`, `drag`, `gravity`, `color` |
| `muzzle` | `x, y`, `angle`, `size`, `dur`, `color` |
| `ring` | `x, y`, `radius`, `dur`, `weight`, `squash`, `color` |
| `laser` | `from: [x,y]`, `to: [x,y]`, `dur`, `grow`, `width`, `color`, `hit`, `muzzle` |
| `tracers` | `from`, `to`, `dur`, `rate`, `speed`, `len`, `spread`, `color` |
| `explosion` | `x, y`, `size`, `dur`, `debris`, `smokeCount`, `palette`, `ring` |
| `scorch` | `x, y`, `radius`; omitted in light mode |

`rand(id,index,salt)`, `range`, `fly`, `rgba`, `glow` and `intensity(events,t)` are available for custom effects; inspect `scripts/tools/p5/lib/particles.js` for signatures. Derive a flash, shake and SFX cue from the same event time. For a shot starting at frame 168, an event at local 1.3 s maps to frame `168 + round(24 * 1.3)` and scene sound time `168 / 24 + 1.3`.

An isolated frame must match a full render. Compute particle position and appearance from its seeded identity and absolute age; do not accumulate particles across frames or use unseeded randomness. `scripts/tools/p5/examples/particles.js` is a runnable example:

```sh
ruby mv.rb 'anim:render[tools/p5/examples/particles.js,output/particles-preview,48,320,180]'
```

## The light layer

The same overlay can detect `ANIM.data.vfx !== undefined` and draw only light onto transparency. Keep the same camera and transforms. Mask occluding HUD/window geometry with `destination-out` so it does not receive the bloom. The Swift `halo` cue adds tight and wide Gaussian blooms to this layer before screen blending; unlike `glow`, it does not bloom the whole picture.

```yaml
source: output/scene/final_overlay_plain.mp4
out: output/scene/final_overlay.mp4
lights: prompts/scene/05_overlay.js
cues:
  - {fx: halo, f: 168, dur: 96, shape: span, fade: 1, amt: 1.0, radius: 11}
  - {fx: flash, f: 199, dur: 7, amt: 0.28, color: "#ffd9a8"}
  - {fx: shake, f: 199, dur: 10, amt: 8}
```

Inspect peak frames at full size: combined halo and flash can white out the action. Keep the HUD and subtitles sharp. A custom halo needs a custom light sketch; the bundled leak/flare/glints sketch does not invent emitter geometry for it.

## Bake between overlay and sound effects

Save the configuration above as `prompts/scene-vfx/cues.yml`, then:

```sh
RUN=scene ruby mv.rb gen:overlay
ruby mv.rb 'vfx:bake[scene]'
SFX=scene-sfx ruby mv.rb sfx:mix
```

`vfx:bake` keeps `final_overlay_plain.mp4`, renders into a temporary file and replaces `final_overlay.mp4` only on success. A receipt hashes the video stream separately from audio. Rerunning starts from the plain picture, so glow never stacks; an audio-only remix is copied onto that picture first. Missing or changed plain footage is an error for a recognized baked output. Rebuild `gen:overlay` to establish a fresh source. A per-scene lock serializes baking; finish the overlay/remix task before starting a bake.

For a distinct final output instead, use ordinary `vfx:render`. Swift VFX requires macOS. Neither workflow makes model calls.
