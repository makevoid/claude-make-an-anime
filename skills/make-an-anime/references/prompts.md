# Character sheets, keyframes, H3 shots and camera language

Use this directive in every character, keyframe and H3 prompt and in every sub-agent brief, followed by specific instructions:

> This asset belongs to a high-quality anime production with television-broadcast polish: on-model characters who are recognisably the real people they are based on, clean expressive acting, deliberate composition and purposeful camera work. Every frame should be worth pausing on.

Never ask for trademarked characters, logos or branded designs, even indirectly: a colour named after a famous game character can produce that character's actual face. Describe the generic object ("a plain green square cushion with a pixel-block texture, no face or design") and let dialogue carry the reference.

Do not instruct a generation model to browse: the coordinating agent researches and supplies the details. Exclude all lettering, captions, subtitles, logos and watermarks; p5 draws every readable word.

## Style bible: `config/style.md`

One paragraph, pasted into every image and H3 prompt through `{{STYLE}}`. Define: medium (cel-shaded 2D TV anime, painted backgrounds), line (thin clean lineart, line weight on silhouettes), shading (one or two cel tones plus soft highlight), eyes and faces (proportion, how realistic), colour (palette anchors in hex for each recurring light: monitor glow, lamp, moonlight, golden hour), backgrounds (painted, detailed, depth haze), lighting (motivated sources, rim light), and what to avoid (3D render look, photorealism, chibi, text). Choose the look from the story and brief; keep it unchanged for the whole production so every scene cuts together.

## Character sheets from reference photos: GPT Image 2.6 Sunburst

`Steps::RefBase` with `photos:` sends the uploaded reference photos to `openai/gpt-image-2.6/sunburst/edit` (quality `high`, `reasoning_effort` `high`, 2752×1536). Structure of `01_ref_base.txt`:

1. "Character design sheet for an anime production. Draw the person shown in the reference photos as an anime character, keeping their real likeness: …" then the likeness anchors you verified in the photos (face shape, hairline, eyebrows, eyes, nose, beard, glasses, colouring) and the age at this point in the story.
2. `{{STYLE}}`
3. Layout on a plain light-grey background: full-body front turnaround, three-quarter, profile and back in a row on the left two thirds; on the right, a head close-up and three expressions named in the plan (e.g. calm focus, warm smile, sleepy). Same outfit in every view; neutral standing pose; whole silhouette inside the frame with margins; consistent scale between views.
4. Outfit for this point in the story, colours in hex if they matter.
5. Exclusions: no text, labels, colour swatches with numbers, logos or watermarks; no extra characters; no photoreal rendering.

For children and siblings, generate each child separately but in the same session of prompts, and state the differences that tell them apart (hair length, parting, face shape, signature colour). Review the whole cast in one board beside the photos.

### Getting the face right (likeness first, style second)

Hair, beard and glasses are easy; the **face** is what people recognise, and the model drifts toward a generic anime face (narrow, angular, big eyes, small nose) unless the prompt and the image order push back. What works:

1. **Front views first.** The edit model weighs the first images most. Put two or three straight-on, well-lit face photos as images 1–3, then three-quarter and profile photos, then (last) any sheet used only as a style reference, and say so in the prompt ("images 1–3 are FRONT views: build the face from them; image 8 is only a style reference"). Use every usable photo, not a sample.
2. **Write a face-anchor checklist from the photos**, one line each, with what to avoid: face shape and width ("broad, full, rounded, wide at the cheeks — not narrow, no sharp cheekbones"), eyes (size, lids, depth — "small, deep-set, heavy-lidded; do NOT enlarge into big round anime eyes"), eyebrows (thickness, height relative to the glasses), nose (length, bridge, tip width), mouth and resting expression, skin undertone, forehead/hairline, build (stocky/slim, neck). Look at the photos and measure; do not guess from a name or a role.
3. **Ask for a large FRONT-view head close-up** on the sheet, so it compares one-to-one with the front photos.
4. **Two passes when needed.** If the likeness pass comes out semi-realistic, keep it (`-v3`) and restyle it in a second edit (`-v4`, `edit_from: <likeness run>`, `photos:` the cast's accepted sheets as style references plus two front photos), with "this is a STYLE change only: keep the face and body proportions exactly", repeating the anchors. A single prompt asking for both likeness and a strong stylisation tends to trade the face away.
5. **Review with `review:likeness[v2,v3,v4]`**: alternatives stacked under the same numbered photo row. Judge the front close-up against the front photos first, then the turnaround. Let the user pick when they are the subject.

Name versions, never overwrite: a rejected sheet stays in its run for comparison.

## Keyframes: composed first frames

`Steps::Keyframes` items edit the sheets into the first frame of each shot. Use `base: false` with `refs: [char-…-v1, loc-…-v1]` and say explicitly which image is which ("the man from image 1, the bedroom from image 2"). Structure:

1. `{{STYLE}}`
2. Shot size and angle (e.g. "medium close-up, slightly low angle, 35mm feel"), subject placement in percent of frame and facing direction, eyeline.
3. The pose at the **first frame** of the action, expression, hands.
4. Set, props and light sources with direction and colour; time of day. Put the character in the world: say which side of the body the light falls on, and put something out of focus in front of them.
5. Space left for p5 elements (a subtitle band, a screen insert).
6. Exclusions: no text on screens or signs (screens show a soft blank glow), no extra people.

For a shot that continues the previous one, set `base:` to that keyframe and change one thing. Generate an `end_image` only when the end pose matters (a head turn that must finish facing camera); otherwise let H3 resolve the action.

## H3 shots: MiniMax H3 Max

`Fal::Models::H3MaxImageToVideo`, `minimax/h3-max/image-to-video`, **768P by default** (H3 offers 480P/768P/1080P; there is no 720P), prompt expansion disabled. `VIDEO_RES=1080P` refines a hero shot. Duration is the shot length (fractional seconds allowed, 0.92–15 s, at least 2 s with target audio; H3 may add up to ~0.7 s). The plate is upscaled to 1920×1080.

Prompt (`prompt:` in `04_shots.yml`): identity and a short style sentence ("hand-drawn 2D anime; the same characters as in the image") → what happens, as two or three timed acting beats ("0–1 s: …; 1–2.5 s: …") → mouth ("speaks the line with natural lip movements; mouth closed before and after") → what must stay unchanged (faces on-model, outfit, background layout, light) → exclusions (no text, no extra people, no new props, no scene change). Anime acting reads best with clear holds and limited, purposeful motion: a blink, a breath, a head tilt, a slow smile, hair and cloth secondary motion, light flicker from a screen.

For a talking shot set `audio: <cast id>`; the shot then receives that character's mouth track from its own position in the scene. Never retime a talking shot.

### Camera language

Write the camera as its own `camera:` field; Shots sends it to H3 as a separate `Camera:` paragraph. A Hash is joined as `key: value; …`. Always state:

- **move**: one move per shot, named precisely (below);
- **from → to**: the framing at the start and at the end (shot size and what is centred);
- **speed and easing**: "very slow", "slow", "steady", "fast whip"; "ease-in", "ease-out", "linear";
- **timing**: when the move starts and stops inside the shot (moves that start after a short hold and settle before the cut feel deliberate);
- **anchors**: what stays fixed in frame (the subject's eyes on the upper third, the horizon level) and what the move reveals or hides;
- **lens/focus** when it matters: "shallow depth of field", "rack focus from the hand to the face at 1.5 s".

Vocabulary, with when to use it:

| Move | Use |
|---|---|
| Locked-off / static | dialogue, comedy timing, holds; the acting carries the shot |
| Slow push-in (dolly in) | growing emotion, a realisation, attention to a face or screen |
| Pull-out (dolly out) | reveal of context or isolation, end of a scene |
| Pan left/right | follow a look or action across a set; reveal a second subject |
| Tilt up/down | scale, a character standing, from object to face |
| Truck / lateral tracking with parallax | establishing shots, walking, layered backgrounds (foreground passes faster) |
| Crane / pedestal down | open a scene from above, arrive at a window or a desk |
| Orbit (slow arc) | a turning-point moment around one character |
| Rack focus | shift attention between two planes without cutting |
| Handheld micro-sway | tension, intimacy; keep it subtle |
| Whip pan / smash zoom | shounen energy, comedic snap, transitions on a hit |

Rules: one primary move per shot; keep faces in frame through the move; do not move the camera during lip-synced dialogue unless the move is very slow; alternate moving and static shots so moves register; match the direction of consecutive moves or cut on a hold; the last shot before a smash cut holds still. Example:

```yaml
camera:
  move: very slow push-in (dolly in), no rotation
  from: medium shot, desk and monitor centred, man at right third
  to: medium close-up on the man's face lit by the monitor
  timing: hold 0.5 s, push 0.5–3 s with ease-in-out, settle before the cut
  anchors: eyes stay on the upper third; monitor edge stays in frame left; horizon level
  focus: shallow depth of field, background bookshelf softly blurred
```

### Action shots

Action is painted with its world in one take. Write "one painted image with the character and the world drawn together" in the keyframe, and name the light on the body. For a run, direct one runner, a camera that travels beside them, and what passes in the foreground and background. [believable-motion.md](believable-motion.md) has a worked example, and `review:believable` checks it.

### Sprite composites

Never for action: `gen:clips` refuses it. A keyed sprite is the last resort for a figure who stays still, on flat chroma green #00B140 with a locked camera (`Steps::Clips`, `key: green`), cropped by the frame so no feet show. For two people talking far apart, use painted panels with a paper cut instead.

## Retakes

If a take drifts off-model, reduce motion, shorten the shot or add an `end_image`. If it invents text, remove quoted words from the visual prompt and restate "screens show a soft blank glow". If the camera ignores the move, simplify to one named move and state the end framing again ("the camera moves forward and slightly down, never up" plus a concrete end framing worked where "descending crane + push-in" did not). Measure it: `review:camera` compares the first and last frame of every H3 shot (zoom, pan, tilt) with the directed `camera:` move; a match score below 0.65 means parallax or big character motion, so judge that strip by eye.

**Hidden cuts and early actions.** H3 sometimes cuts mid-shot to a new framing (a hug that jumps to a close two-shot at 2 s) or does the shot's business too soon (eats the snack while the line is still playing). Neither the camera estimate nor frame-difference or similarity scores separate these from normal motion (tested: the cut scored like a running child), so read the ~4 fps `review/camera/<shot>_strip.jpg` that `review:camera` writes for every shot. Fixes that worked: "ONE CONTINUOUS TAKE with no cuts and no change of shot", "one unbroken move", and timing the business explicitly ("only in the very last half second does he…", after the line). When a take is good up to a defect (lettering appearing on a car as its hatch closes), cut it declaratively with `source_frames: N` (plus `retime: true` if N < `frames`) in `04_shots.yml` rather than editing the downloaded file. Keep the earlier take (manifest history) and record why it was rejected.

## Models and evolving schemas

Fetch `openapi:fetch` and read `openapi:summary`. The wrappers validate known properties/enums/ranges. Add any other Fal model as a Ruby `Fal::Models::Base` subclass, then a service/task. Do not call an SDK or curl directly. Do not silently substitute a model or quality setting.

Official sources: [H3 API](https://fal.ai/models/minimax/h3-max/image-to-video/api), [Sunburst generation](https://fal.ai/models/openai/gpt-image-2.6/sunburst/text-to-image/api), [Sunburst edit](https://fal.ai/models/openai/gpt-image-2.6/sunburst/edit/api), [ElevenLabs Eleven v4](https://fal.ai/models/elevenlabs/tts/eleven-v4/api), [ElevenLabs Music v2.5](https://fal.ai/models/elevenlabs/music/v2.5/api).

## Difficult staging and small repairs

Use [staging-and-review.md](staging-and-review.md) for perspective guides, connected anatomy, pinned endings, recurring marks, natural prop gestures, jumps, travel and playback review. Keep the full palette bible in image prompts; in H3 name only the current shot’s look, light and room, including full colour through the last frame when intended. A list of different palettes can become an unwanted colour transition.

For a replay from another scene, set `from_take: source-run/shot-name`, `frames`, and optional `skip_frames` or `source_frames`. The original take is copied locally with provenance and a content digest; there is no model call. The copy refreshes when the source bytes change, and assembly rejects insufficient frames. Reused footage does not transfer the source scene’s dialogue: rebuild the destination mix and check synchronisation.
