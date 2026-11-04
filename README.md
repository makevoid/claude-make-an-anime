# Make an Anime

A Claude Code plugin that turns a story into a finished anime: character sheets, camera-directed shots, voices, a score, titles, subtitles, sound effects and finishing VFX. It works at any length, from a 12-second battle scene to a full episode.

<img src="https://github.com/user-attachments/assets/58d0fe9c-118d-4f17-8228-798e29b48e56" alt="Three frames from the sample: the EMBER × TEMPEST title card, the layered green-screen composite, and the full MiniMax H3 shot" width="100%">

This 12-second sample was generated with the plugin, using the example bundled in this repo. Sound on:

https://github.com/user-attachments/assets/50875ac6-d6f9-4b5f-b2b3-9f8f576d04fd

| Time | Section | How it is made |
| --- | --- | --- |
| 0–2 s | Title | Drawn in p5 over a colour plate |
| 2–7 s | Layered composite | Two green-screen fighters, moved in p5 over an animated background, with subtitles and a rolling camera |
| 7–12 s | Full H3 | One continuous MiniMax H3 take with no layers, the camera orbiting 180° around both fighters |

It also works at full length: the toolkit was first used for a narrated anime documentary of over 12 minutes, in about 40 scenes. See [Full episodes](#full-episodes).

## Installation

In Claude Code:

```text
/plugin marketplace add makevoid/claude-make-an-anime
/plugin install make-an-anime@make-an-anime
```

The plugin asks for your [Fal](https://fal.ai) API key and stores it as a sensitive option. All paid generation goes through Fal, so you need an account with credit.

You also need these on your machine:

| Tool | Used for |
| --- | --- |
| Ruby 3.2+ and Bundler | The toolkit itself |
| FFmpeg, ImageMagick | Video, audio and image work |
| Python 3 | Green-screen keying, score editing, analysis |
| Node.js 22+ and Chrome | Rendering p5 titles, subtitles and composites |
| macOS 14+ and Swift 5.9+ | Optional: the Core Image VFX pass |

Each project installs its own Ruby, Node and Python packages when the skill runs `setup`, and `doctor` reports anything missing.

## Usage

Ask Claude for what you want:

```text
/make-an-anime Make a 2-minute pilot from story.md, with characters based on the photos in ./refs
```

Claude reads the story, writes a production plan (cast, voices, shot list, every prompt, the number of paid calls) and asks you to approve it. No paid call runs before that approval. It then produces and reviews each step, and retakes shots that fail review.

Reference photos are optional: original characters are designed from text. Use photos of real people only with their consent.

### Generate the sample yourself

```sh
git clone https://github.com/makevoid/claude-make-an-anime
ruby claude-make-an-anime/skills/make-an-anime/scripts/mv.rb init --project ~/anime/shonen --example shonen-battle
cd ~/anime/shonen
ruby mv.rb setup
ruby mv.rb 'fonts:copy[config/fonts.json]'
```

`config/fonts.json` points to macOS system fonts, so change those paths on other systems. Read `docs/PLAN.md`, then record your approval. The commands below are paid, and need your key in `FAL_AI_API_KEY`:

```sh
NOTE='I approve this plan' ruby mv.rb plan:approve

for run in char-kaen-v1 char-arashi-v1 loc-sky-arena-v1; do RUN=$run ruby mv.rb gen:ref_base; done

export RUN=shonen-s01
ruby mv.rb gen:dialogue
ruby mv.rb gen:music
ruby mv.rb gen:mix
ruby mv.rb gen:keyframes
ruby mv.rb gen:clips
ruby mv.rb gen:shots
ruby mv.rb gen:overlay
SFX=shonen-s01-sfx ruby mv.rb sfx:gen
SFX=shonen-s01-sfx ruby mv.rb sfx:mix
ruby mv.rb vfx:build
VFX=shonen-s01-vfx ruby mv.rb vfx:render    # -> output/shonen-s01/final_vfx.mp4
```

The sample used 7 images, 5 H3 clips of 5 s (one was a retake), 4 voice lines with 4 Whisper checks, 1 score and 6 sound effects. It took about 20 minutes. Check current prices on Fal before you run it.

## How a scene is made

Each stage reads prompts from `prompts/<run>/` and writes to `output/<run>/`, so everything can be inspected and redone on its own. Here is what each stage produced for the sample.

### 1. Character and location sheets

The style bible (`config/style.md`) goes into every prompt through `{{STYLE}}`, so the whole cast shares one look. GPT Image 2.5 draws a turnaround and expressions for each character, and those sheets become the references for everything after. The colours and costumes avoid green on purpose, because these characters will be keyed.

**Kaen**, the flame fighter:

<img src="https://github.com/user-attachments/assets/6a59307a-22b5-49c3-9743-4630c2d8edc9" alt="Character sheet of Kaen: turnaround and expressions" width="100%">

**Arashi**, the storm fighter:

<img src="https://github.com/user-attachments/assets/ead8d6f4-bc20-48e8-8160-5f37a35c4adb" alt="Character sheet of Arashi: turnaround and expressions" width="100%">

**The sky arena**, a recurring location:

<img src="https://github.com/user-attachments/assets/a09e4508-786b-401b-96f7-ef2cd3dd4848" alt="Location sheet of a broken arena floating at sunset" width="100%">

### 2. Voices and score, before any animation

Each character gets one ElevenLabs Eleven v4 voice in `config/cast.yml`. Lines carry their start time, and audio tags like `[cold, cutting]` are performed rather than spoken. Line lengths decide the shot lengths, so voices come first:

- `review:dialogue` checks every take with Whisper.
- `dialogue:timeline` catches lines that cross a cut.

ElevenLabs Music v2.5 then composes one score from a plan that follows the scene's beats, and `gen:mix` ducks it under the voices.

### 3. Keyframes

GPT Image 2.5 composes one first frame per shot from the sheets: an empty arena for the background, each fighter alone on flat `#00B140`, and the mid-air clash for the full-H3 shot.

<img src="https://github.com/user-attachments/assets/f25487dd-200e-4adb-81ba-451c24593ab0" alt="The four keyframes: empty arena, Kaen on green, Arashi on green, and the clash" width="100%">

### 4. Background plate

MiniMax H3 animates the empty arena with an orbit around its centre. `roll: [-9, 9]` in `04_shots.yml` adds a virtual camera roll, applied locally in FFmpeg and scaled just enough to hide the corners.

<img src="https://github.com/user-attachments/assets/2d2eebfd-a654-4b90-882f-c9520447ed38" alt="Four frames of the animated arena plate, with the camera orbiting and rolling" width="100%">

### 5. Green-screen performances

H3 animates each fighter with a locked camera, and that character's voice track as target audio so the mouth follows the line. `key: green` turns each clip into a transparent PNG sequence.

<img src="https://github.com/user-attachments/assets/7e352b37-b66d-430b-94a4-08516738198b" alt="Each fighter on green beside the same frame keyed to transparency" width="100%">

### 6. Composite in p5

`05_overlay.js` draws the title, moves the two sprites around a shared centre and rushes them together for the hit at 5.6 s. It adds speed lines, a bloom, shock rings, embers and subtitles. Sprites are drawn inside `Anim.withRoll`, so they turn with the plate, while subtitles stay level.

From left to right: the plate, the p5 layer, and the composite after sound and VFX.

<img src="https://github.com/user-attachments/assets/800ee8c7-1427-496a-9945-a72d2f7e12c7" alt="The plate, the transparent p5 layer, and the final composite of the same frame" width="100%">

### 7. The same fight with no layers

For comparison, the last five seconds are a single H3 take from the clash keyframe. It needs one clip and no compositing, and the camera passes behind Kaen and ends on the opposite side of the fight. You get less control over timing, and the mouths are not synced to the finisher lines.

<img src="https://github.com/user-attachments/assets/f92874fe-063e-4b13-abcd-6ed87e7e8bf4" alt="Four frames of the continuous H3 shot, with the fighters swapping sides as the camera orbits" width="100%">

Painted full-frame shots like this are the default. Layers are for moments that need exact placement and timing: [layered-scenes.md](skills/make-an-anime/references/layered-scenes.md) explains when to use them.

### 8. Sound and finish

`sfx:gen` creates sound effects with Stable Audio, and `sfx:mix` places them from a cue list and levels them against the mix. `vfx:render` then adds impact punches, RGB split, glow and grain with Swift Core Image, on frame-accurate cues.

## How a scene is edited

Everything is a file, and every step is cached, so a change only redoes what it affects. Replaced takes are kept in `output/<run>/rejected/`. These are the real edits made to the sample after its first pass:

| What was wrong | The edit | Cost |
| --- | --- | --- |
| Two pairs of voice lines overlapped | Changed `at:` in `03_dialogue.yml`, then `gen:dialogue` and `gen:mix` reused the takes | Free |
| Arashi's hair and coat turned black partway through her clip | Added the colours to the prompt, then `ONLY=arashi FORCE=1 gen:clips` | 1 H3 clip |
| An olive fringe around Kaen's flames, where they lit the green | Added `low: 8` to the clip, then `RECUT=1 ONLY=kaen FORCE=1 gen:clips` re-keyed the downloaded clip | Free |
| Fighters too large, hiding each other | Edited `05_overlay.js` and checked single frames with `'anim:preview[70,100,134]'` | Free |
| The score faded out at 10 s, under the last line | Held the climax chord (below) and set `music_from` | Free |

The score edit, then the rebuild of everything that depends on it:

```sh
.venv/bin/python3 -I tools/python/score_tool.py freeze \
  output/shonen-s01/03_music_12s.wav output/shonen-s01/03_score_end.wav 9.0 8.5 9.0 12 -19 -23
# in config/generations.rb: music_from: "output/shonen-s01/03_score_end.wav"
ruby mv.rb gen:music
ruby mv.rb gen:mix
ruby mv.rb 'scene:reaudio[shonen-s01]'        # new mix on the rendered picture, no re-render
SFX=shonen-s01-sfx ruby mv.rb sfx:mix
VFX=shonen-s01-vfx ruby mv.rb vfx:render
```

A retake needs a changed prompt. Fal requests are stored as receipts by their exact input, so `FORCE=1` with an unchanged prompt fetches the same result again, at no charge.

Local review tools help decide what to retake:

| Command | What it shows |
| --- | --- |
| `review:camera` | The camera move each shot made, with frame strips to read by eye |
| `review:clips` | A board of the keyed sprites and their coverage |
| `review:dialogue` | What Whisper heard in each take (paid) |
| `dialogue:timeline` | Lines against shots and cuts |
| `audio:seams` | Abrupt music changes at scene joins and inside a score |

### What is still imperfect in the sample

- The sprites carry the light of their keyframes and have no contact shadow, so they sit less firmly in the scene than the full-H3 shot.
- A faint warm edge remains around Kaen's flames.
- Arashi still darkens a little under the lightning in the last second of her clip.
- The full-H3 mouths are not synced to the finisher lines, which are shouted over the action.

## Full episodes

A longer project uses the same steps, one run per scene, plus:

- `scene:new[ep01-s05,480]` to scaffold a scene, with one config file per scene so several agents can work at once
- `config/episodes/ep01.yml` for the playing order
- `episode:preview` to join scenes, levelling the voices across them (`VOICE_DB`) and fading the seams (`SEAMS=1`)
- production waves with sub-agents (`work:next`, `work:accept`), starting with the opening and the emotional peak

[full-episode.md](skills/make-an-anime/references/full-episode.md) has the complete workflow.

## Repository layout

```text
.claude-plugin/                   plugin and marketplace manifests
skills/make-an-anime/
  SKILL.md                        what Claude follows
  references/                     planning, prompts, camera language, audio, episodes
  examples/shonen-battle/         the sample's story, config, prompts and plan
  scripts/
    mv.rb, mcp.rb                 CLI and MCP entry points
    lib/fal/                      Fal queue client with receipts, and model wrappers
    lib/pipeline/steps/           RefBase, Dialogue, Music, Mix, Keyframes, Shots, Clips, Overlay
    lib/media/, lib/toolkit/      FFmpeg, ImageMagick, Python, p5 and Swift wrappers; project tools
    tools/p5/                     headless renderer and the Anim library
    tools/python/                 keying, tracking, analysis, score editing
    tools/vfx/                    Swift Core Image renderer
    spec/                         RSpec suite
```

The specs never call Fal. They run from `skills/make-an-anime/scripts` after `npm ci`, with `MV_PYTHON` pointing at a Python that has `requirements.txt` installed:

```sh
bundle exec rspec --tag core
bundle exec rspec --tag media    # includes the whole sample scene with synthetic media
```

## License

[MIT](LICENSE)
