# Plan: Sample Seven

The smallest complete plan: every heading of `assets/plan-template.md`, one line each where one line is enough. Longer
plans that grew through review: `examples/02-final-inspection`, `03-riverbank-bout`, `04-too-salty`.

## Brief and approval scope

`docs/BRIEF.md`, one scene of 14 s (336 frames), English voices with subtitles, 16:9, 24 fps, H3 768P delivered at
1080p. Prices are not quoted here: check the fal.ai page of each model before running.

| Model | First pass | Retake ceiling |
| --- | --- | --- |
| GPT Image 2.6 (quality high, reasoning high) | 3 sheets + 6 keyframes | 4 more |
| MiniMax H3 Max 768P | 5 takes, 13 s generated | 3 more |
| ElevenLabs Eleven v4 | 3 lines | 3 more |
| ElevenLabs Music v2.5 | 1 score of 14 s | 1 more |
| ElevenLabs Sound Effects v3 | 4 sounds | 2 more |
| Whisper | 3 line checks | 3 more |

## Creative direction

Slice of life with one shounen beat. Hook: a woman staring at a flask at 4 a.m. Peak: the colour turns and she runs.
Payoff: he repeats her words back. Locked cameras for the quiet, one travelling camera for the run, a white smash into
it. Style bible: `config/style.md`. Type: Arial Bold for subtitles and the title.

## Cast

| Id | Character | Voice | Identity run |
| --- | --- | --- | --- |
| mei | Mei, 24, graduate student: loose ponytail, white lab coat, mustard sweater | Alice | char-mei-v1 |
| ono | Professor Ono, 68: white moustache, grey cardigan, tea cup | Bill | char-ono-v1 |

Location: `loc-lab-v1`, a long lab with Mei's lamp-lit bench at the left end and Ono's desk under the windows at the
right. Mei faces left to her flask, runs left to right, and her hand enters Ono's shot from the left.

## Scene: lab-s01

| Frames | Shot | Camera | Source | Sound |
| --- | --- | --- | --- | --- |
| [0, 84) | lab: Mei watches the flask | locked wide | H3, same first and end frame | Ono off screen at 0.6 s: "Staring at it won't make it go any faster." |
| [84, 144) | mei: close, eyes on the flask | locked | H3, Mei's mouth track | Mei at 3.8 s: "It might." |
| [144, 192) | flask: clear turns cobalt | locked | H3, first and end frame | score turns |
| [192, 228) | dash: she runs the aisle | tracking beside her | H3 2.5 s retimed to 1.5 s | white smash, chair, footsteps |
| [228, 300) | ono: looks at the flask, then at her | locked | H3, Ono's mouth track | knock at 9.5 s; Ono at 10.4 s: "...Fine. It might." |
| [300, 336) | title | none | black frame, p5 title | score resolves |

Action check: one runner, painted with the lab in one take, the camera travelling with her; nobody is keyed. The blue
is a colour, never a glow. Prompts: `prompts/lab-s01/`.

## Production waves

Mei's sheet and the lab first, then Ono; voices; score and mix; keyframes; takes, `dash` and `flask` first because they
can fail; overlay, SFX, VFX. A pilot this short runs serially.

## Review and delivery

`review:likeness` on the sheets, `review:dialogue`, `review:believable` before and after the takes, `review:camera` on
`dash`, every shot watched at speed with sound, mouths moving only on their own lines, frame count 336. Deliver
`output/lab-s01/final_vfx.mp4`, the sheets, the cast table and this plan.
