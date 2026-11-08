# A game on a screen

Use this for an original game interface inside a film, or for an intentional game-like diagram. Generate artwork without text, cut it locally, then draw all readable words, numbers, cursors and event timing in p5. Choose art and UI conventions for the story's era without copying a specific game's units, branding or layout. Use fonts licensed for the intended delivery; no font files are bundled.

The optional modules `Anim.rts`, `Anim.mission` and `Anim.court` are loaded after `Anim.particles`. They provide a concrete RTS composition, mission-map primitives and court diagrams; other genres can reuse the asset tools and particles independently.

## Artwork and cutting

Starter prompts in `assets/game-screens/` cover `console.txt`, `map.txt`, `units.txt`, `icons.txt` and `portrait.txt`. Adapt them to the approved visual direction and register each as a normal `gen:ref_base` run. Paid calls follow the production plan and existing credential workflow. A 4-second screen does not require generating a full video if p5 can animate the planned action from these sheets.

The console should contain empty flat-black screens; the sprites should have clear gaps. Inspect whether the returned file actually uses transparency, magenta or black. The cutting tools support all three; do not assume a requested key colour was returned.

Run local tools through Ruby with JSON recipes, which allow commas and spaces inside paths and arrays:

```json
{"mode":"sprites","source":"output/game-units/01_ref_base.png","out":"output/game-art/units","names":["trooper","walker","tank","gunship","spider","crawler","skiff","stilt"],"key":"alpha"}
```

```sh
ruby mv.rb 'game:cut[config/cut-units.json]'
```

| `mode` | Required recipe fields | Options |
| --- | --- | --- |
| `sprites` | `source`, `out` directory, `names` array | `key` (default alpha), `min_px`, `min_len`, `gap`, `margin` |
| `grid` | `source`, `out` directory, `names` array | `key` (default black), `min_px`, `min_len`, `gap`, `size`, `inset` |
| `frame` | `source`, `out` PNG, `slots` JSON | `key` (default alpha), `dark`, `scale`, `min_area` |
| `fit` | `source`, `out`, `width` | `crop: [x,y,w,h]` |

Sprite/icon names must be unique plain identifiers. A count mismatch stops instead of silently dropping a cell. `frame` locates connected dark rectangular areas, makes them transparent and writes their measured bounds. Inspect the holes and slot ordering; merged or decorative black regions can require a cleaner source or adjusted thresholds. `fit` resizes terrain/portraits and can crop first.

`Anim.rts.load({dir, units, icons})` expects `map.jpg`, `console.png`, `console_slots.json`, `portrait.png`, and `units/<name>.png` / `icons/<name>.png` below `dir`. It assigns the large console slots left-to-right to portrait/minimap/info/gauge and small slots to commands; `game.hud.screens` overrides the large-slot labels. Keep the required empty screens distinct.

## Choreography

`scripts/tools/p5/examples/game-screen.js` is a generic starting sketch. Supply a data JSON such as `{"dir":"/output/game-art","units":["trooper"],"icons":["move"]}` via the renderer's `game` data entry when calling `Media::Anim#render` from a project Ruby recipe. The header of `rts.js` documents its game object: unit positions as functions of time, deaths, events, camera, selection, cursor, commands, portrait activity, minimap and counters.

Keep named event times in one place and derive visual, light and sound cues from them. A cursor should travel to the button it presses. Minimap positions should follow the actual units. Tiny sprites may slide convincingly for a brief screen insert; larger or longer shots need pose cycles and facing changes. Single-pose art is not a walking animation.

`Anim.mission` adds floor, fog, beacon, path and unit helpers. Configure `R.bezel = {box: [x,y,w,h], inset: [left,top,right,bottom], corner: pixels}` from your measured console art before calling `begin`/`end`; there is no universal pixel crop. Its bezel is nine-sliced. `Anim.court.half(box)` and `.full(box)` produce diagram geometry; the included court lines are illustrative and must be adapted to the sport, era and intended proportions. `drillSim` is an illustrative eight-second drill derived from a formation configuration; frames may be requested out of order. Longer or different choreography needs its own simulation or time functions.

See [particles-and-glow.md](particles-and-glow.md) for `mode: 'light'`, occlusion and the `halo` pass. Size a screen effect's sound for the in-scene speakers; distant desktop audio need not have cinematic sub-bass. Measure the surrounding mix and inspect flashes for whiteouts.

## Face icons

Crop accepted character faces into a consistent grid, request one edit using `assets/game-screens/face-icons.txt`, then cut the result. The input spec describes only the chosen sheets and measured face boxes:

```json
{"cols":2,"rows":1,"cell":[460,520],"gap":40,"margin":60,"faces":[{"name":"pilot","sheet":"output/char-pilot/01_ref_base.png","box":[600,400,240]},{"name":"rival","sheet":"output/char-rival/01_ref_base.png","box":[600,400,240]}]}
```

`box` is centre x/y and crop width; optional `scale` converts measurements from a downscaled inspection image. Use a `game:faces` recipe `{"mode":"build","spec":"config/faces.json","out":"output/faces-collage.png"}`. After the approved image edit, use `{"mode":"cut","spec":"config/faces.json","source":"output/faces-edited.png","out":"output/game-art/faces","size":256}`.

The cutter stops on ambiguous counts. Inspect the sheet before explicitly setting `grid_fallback: true`; this evenly splits the detected content bounds and still needs visual identity review. Verify every returned cell against its source face before using the name mapping. Project-specific face sheets, photos and character names are not part of the plugin.
