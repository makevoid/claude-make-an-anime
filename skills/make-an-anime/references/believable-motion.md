# Believable footage

Footage has to look like it was really shot and drawn as one piece. "Realistic" here means physically believable, not photoreal: the style bible still sets the anime look. Light, contact, motion and camera must agree across the whole frame. When they don't, the result looks pasted together and AI-generated, however good each part is.

Check every shot against this page: when you plan it, before you pay for it, and when you review it.

## The rules

1. **Action is never on green screen.** A keyed figure has no ground contact, no shared light and no shared camera, so running, punching, falling or jumping on green looks ridiculous. Generate the character and the world in the same H3 take.
2. **One runner per shot, with a camera that travels.** Show one person running with the world moving behind them, and let the cut bring people together. Two people running at each other in one wide shot comes out as two treadmills, even with no key.
3. **Green screen is only for someone who stays put.** It can carry a calm line or a held pose, with the figure cropped by the frame so no feet show. Even then, prefer painted panels (below).
4. **Paint people into the world.** Keyframes say "one painted image with the character and the world drawn together", name the light direction on the body, and put out-of-focus grass or props in front of the figure. Foreground overlap sells the depth.
5. **Effects must not sit on top of the painting.** Glows, rings, auras, speed lines and embers read as pasted on. Sell a blow with the cut, a short jolt, a brief flash and the sound.
6. **Keep the camera partial.** A partial arc reads as a camera operator. A full spin reads as a stunt.

## Two people talking who are far apart: the paper cut

To put them on one screen, use a manga page instead of compositing them into one background.

1. Make one keyframe per person, each with their own copy of the location, with the subject in their side of the frame. Use the same location sheet for both, and tell each which side the sun is on.
2. Animate each as a full-frame take in `04_clips.yml` with `key: none`, a locked camera, `audio:` and `audio_at:`. The wind, water and clouds move in the same generation.
3. Give the shot under them `color: "#000000"` in `04_shots.yml`, and draw the page in the overlay:

   ```js
   Anim.paperCutPanels(
     () => this.left.draw(this.left.at(t), x1, y, h),
     () => this.right.draw(this.right.at(t), x2, y, h),
     { cut: [1040, 880], gutter: 26 }
   );
   Anim.subtitles(t, lines, { font, x: 470, skip: (l) => l.character !== "left-id" });
   Anim.subtitles(t, lines, { font, x: 1450, skip: (l) => l.character !== "right-id" });
   ```

   Scale each panel a little so the person fills it, and keep raised hands clear of the cut. Place each subtitle under its speaker's panel.

## A run that works

The keyframe already looks like a moving camera: one person in side view, sharp, with the near grass smeared into horizontal streaks and the background softly streaked along the direction of travel.

```yaml
- name: charge
  image: charge
  frames: 36
  seconds: 2.5
  source_frames: 60   # about 1.7x, a real sprint cadence
  retime: true
  prompt: "... He sprints flat out from left to right ... He stays in the centre of the frame because the camera travels with him. The whole world rushes past behind him from right to left the entire time: the near grass whips through the foreground, the bushes and the path slide quickly past, the river and the bridge drift more slowly far behind, a strong layered parallax."
  camera:
    move: fast lateral tracking shot, the camera travels sideways alongside the runner at his exact speed, never stopping
    to: the same side view of him, much further along the riverbank
    timing: full speed from the first frame to the last
```

Name something large in the near background, such as bushes or a fence. It gives the eye something to see passing.

## Detection

`RUN=<run> ruby mv.rb review:believable` is local and free, and works before and after generating. Run it when the prompts are written and again after `gen:shots`.

| Check | When | Result |
|---|---|---|
| Action words in a keyed clip's prompt | Before any paid call | `gen:clips` refuses |
| A run whose camera does not travel | Before any paid call | `gen:shots` refuses |
| Several runners in one shot | Before any paid call | `gen:shots` refuses |
| The near ground of a run moves under 0.20 frame widths per second | After the take exists | Issue: retake with more camera travel |
| A colour split (`rgb`) above 0.05 in the VFX cues | Before the render | Issue: it garbles the picture |
| Keyed sprites, plate rolls, full turns, pasted-on effects | Any time | Warning: look at it |

The measure uses only the near ground, because in a good tracking shot the sky and a far bridge barely move. Calibration on real H3 takes: the rejected two-man run scored 0.11, the tracked single runner 0.28, and static or dialogue shots 0.00–0.04. That is only two runs, so read the frame strip too. A locked shot of someone who really crosses the frame would fail this measure.

Word matching can be wrong, as in "runs a hand through his hair". Then the item states why it is fine, and the review prints the reason:

```yaml
believable: no running, only a hand gesture
```

Use this only for a word that was misread, never to push real action through.

**What the tools cannot catch:** a p5 sketch that slides a sprite across the frame, wrong light on a figure, floating feet, or a run where the ground moves but the legs look wrong. Those need your eyes.

## Review by eye

For scale, anatomy, contact, pinned end frames, pacing and a written review record, use [staging-and-review.md](staging-and-review.md). These checks complement the metrics below.

Watch at normal speed, then look at a dense frame board around every hit and cut. Sparse boards miss short glitches.

- Do the feet land where the body travels, and does anyone run in place?
- Does the light on each person match the sky and ground behind them?
- Does anyone have an outline, a halo or a hard edge against the background?
- Does each blow connect at contact, on the frame of its sound?
- Does any glow, ring or line look stuck on top of the picture?
- Look at the frames right after a flash. A bright effect can hide a broken frame in a sparse check.

If any of these fails, the shot fails, however good the rest of it looks.
