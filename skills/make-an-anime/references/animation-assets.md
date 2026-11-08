# Animation asset preparation

Use these local tools to separate props, poses, decorative elements or portraits from generated sheets. They prepare images for an animation; layout, styling and choreography belong to the project's sketch. Paid artwork generation follows the approved production plan.

## Sheet cutting

Inspect whether the sheet actually has transparency, magenta or black behind the artwork. Use the matching `key`, and give each intended output a unique plain identifier. The cutter finds rows and then elements left-to-right from visible coverage; it stops when the detected count differs from the supplied names. It does not infer identities or animation frame order.

Save a JSON recipe, then run it from an initialized project:

```json
{"mode":"sprites","source":"output/prop-sheet/01_ref_base.png","out":"output/art/props","names":["leaf","flower"],"key":"alpha"}
```

```sh
ruby mv.rb 'assets:cut[config/cut-sprites.json]'
```

| Mode | Required recipe fields | Options |
| --- | --- | --- |
| `sprites` | `source`, `out` directory, `names` array | `key` (default alpha), `min_px`, `min_len`, `gap`, `margin` |
| `grid` | `source`, `out` directory, `names` array | `key` (default black), `min_px`, `min_len`, `gap`, `size`, `inset` |
| `frame` | `source`, `out` PNG, `slots` JSON | `key` (default alpha), `dark`, `scale`, `min_area` |
| `fit` | `source`, `out`, `width` | `crop: [x,y,w,h]` |

`sprites` preserves each cut-out's proportions and alpha. `grid` produces square tiles while preserving their background; its `key` is used for detection, not background removal. Use it for illustrated panels or icons. A pose sheet is not automatically a coherent motion cycle: inspect order, registration and transitions before animating it.

`frame` finds connected dark rectangular apertures in decorative artwork, makes them transparent and writes their measured bounds to `slots` as `{w,h,top,slots:[[x,y,w,h],...]}`. Bounds are sorted by descending area; they have no assigned meaning. Inspect them before placing content underneath. This is a flat image operation, not perspective projection. `fit` optionally crops and then resizes an opaque background or portrait to the requested width.

## Portrait collages

Crop accepted character faces into a consistent reference grid for one image edit, then split the edited result. The spec selects source sheets and measured face boxes:

```json
{"cols":2,"rows":1,"cell":[460,520],"gap":40,"margin":60,"faces":[{"name":"lead","sheet":"output/char-lead/01_ref_base.png","box":[600,400,240]},{"name":"friend","sheet":"output/char-friend/01_ref_base.png","box":[600,400,240]}]}
```

`box` is centre x/y and crop width; optional `scale` converts measurements taken from a downscaled inspection image. Crop height follows the cell aspect ratio. Use a build recipe:

```json
{"mode":"build","spec":"config/faces.json","out":"output/portrait-collage.png"}
```

```sh
ruby mv.rb 'assets:faces[config/build-faces.json]'
```

Adapt `assets/portrait-grid.txt` to the approved art direction for the image edit. For the returned sheet, run the same task with `{"mode":"cut","spec":"config/faces.json","source":"output/portraits-edited.png","out":"output/art/portraits","size":256}`. The cutter removes the detected background and pads each portrait to a square.

Ambiguous counts stop the cutter. Set `grid_fallback: true` only after inspecting the sheet; it evenly divides the detected content bounds and still needs identity review. Verify every returned portrait against its named source. Neither the collage tool nor the prompt imposes a particular genre or character proportions.

## Animate with the existing timeline

Use `Anim.progress`, `Anim.tween`, `Anim.envelope` and normal p5 transforms to place and move prepared artwork. Derive every frame from time so isolated previews match full renders. `scripts/tools/p5/examples/sprite-motion.js` moves a prop over transparency without any interface or game layout. Its data JSON is `{"sprite":"/output/art/props/leaf.png"}`. Render from a project Ruby recipe:

```ruby
Media::Anim.new.render("tools/p5/examples/sprite-motion.js", "output/prop-motion",
  width: 320, height: 180, fps: 24, frames: 48,
  data: { assets: "config/assets.json" })
```

Renderer image paths start at the project root. For timed video cut-outs use `Anim.clip`; for emitted light and atmospheric effects see [particles-and-glow.md](particles-and-glow.md). Moving a static prop is useful for layered composition, but moving an entire character image does not supply body performance.

## Migration from 0.5.0

`game:cut` and `game:faces` are now `assets:cut` and `assets:faces`; recipe fields are unchanged. Ruby callers use `Media::AnimationAssets` from `lib/media/animation_assets.rb`. The RTS, mission-map and court modules, their screen example and genre-specific art prompts have been removed. Existing initialized projects retain their own toolkit copies; their files are not automatically rewritten by a plugin update.
