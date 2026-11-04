# Make an Anime

A Claude Code plugin that turns a story into a finished anime: character sheets, camera-directed shots, voices, a score, titles, subtitles, sound effects and finishing VFX. It works at any length, from a 12-second scene to a full episode.

<img src="https://github.com/user-attachments/assets/6fdf8671-7a8d-4893-8b34-c265b88a564a" alt="Four frames, one from each example: two friends by a vending machine, a scientist and his assistant in a lab, a Muay Thai fighter against a karate fighter at sunset, and a grandmother and granddaughter in an omelette shop" width="100%">

## Examples

All four were made with the plugin, with Japanese voices and English subtitles, and they show how far the same steps can stretch. Sound on.

### The Last One: slice of life, 12 s

Two university friends have just missed the last train home. Across the rice fields it shrinks into the distance, and the only question left is what to get from the vending machine.

https://github.com/user-attachments/assets/4be1633c-94f1-4c79-97c5-e8a69d96edc2

### The Invention of the Century: comedy, 20 s

A theatrical scientist unveils a shrinking fluid in his cramped lab. His deadpan assistant thinks it's melon soda, and then she eats the evidence.

https://github.com/user-attachments/assets/7ec2cd36-a097-406c-b1a9-072a2deb27ed

### One Round at the River: fight, 17 s

A cocky Muay Thai fighter challenges a calm karate man to one fight on a riverbank at sunset, with hard hand-to-hand contact and no superpowers.

https://github.com/user-attachments/assets/9be8bfb9-86dc-4d77-ba8d-c2e7a2b92733

### Too Salty: cooking drama, 74 s

For 91 days, Hana has tried to make her grandmother's rolled omelette, and every morning she hears the same verdict. Then one morning she leaves out the salt. This is the longest of the four, a whole short story told in 19 shots.

https://github.com/user-attachments/assets/42b3fed6-5dce-4b97-9209-a7e25204336e

The toolkit also works at full length: it was first used for a narrated anime documentary of over 12 minutes, in about 40 scenes. See [Full episodes](#full-episodes).

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

## How a scene is made

Each stage reads prompts from `prompts/<run>/` and writes to `output/<run>/`, so everything can be inspected and redone on its own.

<img src="https://github.com/user-attachments/assets/2f8d9c6d-0b09-4e4f-aa25-ce396cb5acaa" alt="One shot of Too Salty at four stages: the character sheet, the painted keyframe, a frame of the animated take, and the finished frame with subtitles" width="100%">

1. **Character and location sheets.** A style bible (`config/style.md`) goes into every prompt, so the whole cast shares one look. GPT Image 2.5 draws a sheet for each character and location, and those sheets become the references for everything after.
2. **Voices and score.** Each character gets one ElevenLabs voice in `config/cast.yml`. Voices come before animation because line lengths decide shot lengths. ElevenLabs Music then composes one score, and `gen:mix` ducks it under the voices.
3. **Keyframes.** GPT Image 2.5 paints the first frame of each shot from the sheets.
4. **Shots.** MiniMax H3 animates each keyframe as one continuous take, with the camera move written into the prompt and the speaker's voice as target audio so the mouth follows the line. Held stills and colour inserts cost nothing. For moments that need exact placement, [layered scenes](skills/make-an-anime/references/layered-scenes.md) composite green-screen sprites over a painted plate.
5. **Overlay.** A p5 script (`05_overlay.js`) draws titles, subtitles, fades and any composite work.
6. **Sound.** `sfx:gen` creates sound effects with Stable Audio, and `sfx:mix` places them from a cue list and levels them against the mix.
7. **Finish.** `vfx:render` adds grain, glow or impact effects with Swift Core Image, on frame-accurate cues.

The same steps as commands, once a project and its prompts exist:

```sh
export RUN=my-scene
ruby mv.rb gen:dialogue
ruby mv.rb gen:music
ruby mv.rb gen:mix
ruby mv.rb gen:keyframes
ruby mv.rb gen:shots
ruby mv.rb gen:overlay
SFX=my-scene-sfx ruby mv.rb sfx:gen
SFX=my-scene-sfx ruby mv.rb sfx:mix
ruby mv.rb vfx:build
VFX=my-scene-vfx ruby mv.rb vfx:render    # -> output/my-scene/final_vfx.mp4
```

Check current prices on Fal before you run anything. For scale, *Too Salty* took 4 sheets, 22 keyframe images, 23 H3 takes, about 22 voice takes, 1 score and 9 sound effects, retakes included.

## How a scene is edited

Everything is a file and every step is cached, so a change only redoes what it affects. Replaced takes are kept in `output/<run>/rejected/`. These are real edits from the examples:

| What was wrong | The edit | Cost |
| --- | --- | --- |
| Two voice lines overlapped | Changed `at:` in `03_dialogue.yml`, then `gen:dialogue` and `gen:mix` reused the takes | Free |
| A voice take said its word twice | Added `gate_s` to mute the first one | Free |
| A tear ran down Hana's cheek | Repainted the keyframe and changed the prompt, then `ONLY=outburst FORCE=1` on `gen:keyframes` and `gen:shots` | 1 image and 1 H3 take per try |
| An umbrella vanished from the background mid-shot | Painted an end frame that keeps it, and set `end_image` on the shot | 1 image and 1 H3 take per try |
| Steam washed out a tray of omelettes | Replaced the take with a slowly zooming still of its keyframe | Free |

A retake needs a changed prompt. Fal requests are stored as receipts by their exact input, so `FORCE=1` with an unchanged prompt fetches the same result again, at no charge.

Local review tools help decide what to retake:

| Command | What it shows |
| --- | --- |
| `review:camera` | The camera move each shot made, with frame strips to read by eye |
| `review:dialogue` | What Whisper heard in each take (paid) |
| `dialogue:timeline` | Lines against shots and cuts |
| `audio:seams` | Abrupt music changes at scene joins and inside a score |

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
  examples/                       a starter project for `init --example`
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

The specs never call Fal unless you authorize the live spec. They run from `skills/make-an-anime/scripts` after `npm ci`, with `MV_PYTHON` pointing at a Python that has `requirements.txt` installed:

```sh
bundle exec rspec --tag core
bundle exec rspec --tag media    # includes a whole scene with synthetic media
```

## License

[MIT](LICENSE)
