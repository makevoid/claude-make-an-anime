# Layered scenes: green-screen characters over an animated background

**Do not use this for action.** A keyed fighter has no ground contact, no shared light and no shared camera, so a run, a punch or a fall looks ridiculous, and `gen:clips` refuses it. Read [believable-motion.md](believable-motion.md) first.

Painted full-frame H3 shots are the default: they are one pass, and light, depth and contact come free. For two people talking far apart, painted panels with a paper cut are better than this recipe. Layers are the last resort, for someone who stays still and must act exactly on cue, cropped by the frame so no feet show.

No bundled example keys a performance. `examples/03-riverbank-bout` first opened on keyed sprites, and review rejected them as green screen: its painted panels (`key: none`) are the pattern to copy. `spec/pipeline_spec.rb` exercises the keying itself.

## The recipe

1. **Animate the empty background.** A keyframe with the location and no people, then an H3 shot in `04_shots.yml` with clouds, smoke and debris and a named camera move. Forbid people in the prompt.
2. **Perform each character alone.** A keyframe edited from the character's sheet on flat `#00B140`, and a `04_clips.yml` item:

   ```yaml
   - name: kaen
     image: kaen-green
     seconds: 5
     frames: 120
     audio: kaen          # that character's mouth track from the Dialogue step
     audio_at: 2.0        # the scene second this clip starts at, so frame i is scene time 2.0 + i/24
     key: green
     prompt: >-
       {{STYLE}} The same man as in the image, on-model, alone. 2.8-4.4 s: he shouts his line... The flat green background stays one flat colour, no floor, no shadow, no green on him.
     camera: { move: "locked-off, the camera does not move at all" }
   ```

   Keep any green out of costumes, hair and effects, and lock the camera: the motion comes from p5.
3. **Compose in p5.** `Anim.clip(name)` gives the sprite; `clip.at(t)` picks the frame that lip-syncs at scene time `t`, and `clip.draw(frame, x, y, height)` draws it. `examples/03-riverbank-bout/prompts/bout-s01/05_overlay.js` draws clips the same way, unkeyed.
4. **Turn everything with one camera.** `roll: [from, to]` on a shot rolls its plate, eased, in local ffmpeg, scaled just enough to hide the corners. Draw sprites inside `Anim.withRoll(frame, fn)` and they turn with the plate. Subtitles drawn outside it stay level.

## Effects in `tools/p5/lib/battle.js`

`Anim.titleSlam`, `Anim.speedLines`, `Anim.shockRing`, `Anim.impactBloom`, `Anim.embers` (give near layers a larger `depth`), `Anim.aura` (a glow that follows a sprite's alpha), `Anim.flash`, `Anim.shotAt`, `Anim.rollAt`, `Anim.withRoll`.

## Review

- Look at the key on light and dark: hair, hands, feet, spill. `RECUT=1 ONLY=<name> FORCE=1 gen:clips` re-keys a downloaded clip for free.
- A sprite has no contact shadow, and it carries the light of its keyframe. Direct the light of the green keyframe to match the plate, and crop the figure so no ground contact shows. If it still looks pasted on, paint the shot instead.
- Check the mouth against the line at normal speed: `audio` pins the track but is not proof of lip-sync.
