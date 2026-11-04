# Plan: EMBER × TEMPEST test scene

## Brief and approval scope

A 12 s, 24 fps, 16:9, 1080p test of the whole pipeline with original characters: 288 frames in one scene run, so the
score is unbroken. Prices are not quoted here: check the fal.ai pages of each model before running.

| Model | First pass | Retake ceiling |
| --- | --- | --- |
| GPT Image 2.5 Sunburst xhigh | 3 sheets + 4 keyframes = 7 images | 4 more |
| MiniMax H3 Max 768P | 4 clips of 5 s = 20 s | 2 clips more |
| ElevenLabs Eleven v4 | 4 lines | 4 more |
| ElevenLabs Music v2.5 | 1 score of 12 s | 1 more |
| Stable Audio SFX | 6 sounds | 3 more |
| Whisper | 4 line checks | 4 more |

## Creative direction

Shounen battle at full volume. Hook: the title slam. Peak: the first clash at 5.6 s, topped by the orbit in the last
shot. Style bible: `config/style.md`. Type: Impact title, Arial Bold subtitles, copied by `fonts:copy`.

## Cast

| Id | Character | Voice | Identity run |
| --- | --- | --- | --- |
| kaen | Adult man, flame fighter: crimson hair, charcoal jacket, white sash | Callum | char-kaen-v1 |
| arashi | Adult woman, storm fighter: silver ponytail, indigo coat | Charlotte | char-arashi-v1 |

Location: `loc-sky-arena-v1`, a broken arena floating at sunset, split sky.

## Scene: shonen-s01

| Frames | Section | Picture | Sound |
| --- | --- | --- | --- |
| [0, 48) | Title | p5 on a colour plate: title slam, split light, embers | Score opens on a hit, slam SFX |
| [48, 168) | Composite | H3 empty arena with orbit + plate roll −9°→9°, two keyed H3 fighters moved by p5 inside the same roll, clash at frame 134, speed lines, bloom, shock rings | Arashi 2.1 s, Kaen 4.75 s, clash SFX |
| [168, 288) | Full H3 | One H3 take, 180° orbit, no layers | Finisher names at 7.2 s and 10.05 s |

Prompts: `prompts/shonen-s01/`. Acceptance: on-model faces, clean key edges, camera does the directed move, no invented
text, frame count 288, every line audible over the score, subtitles readable.

## Delivery

`output/shonen-s01/final_vfx.mp4`, the character sheets and this plan.
