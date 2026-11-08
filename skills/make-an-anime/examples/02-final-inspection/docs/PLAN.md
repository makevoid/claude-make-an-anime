# Final Inspection: production plan

## Brief and approval scope

Story: `docs/BRIEF.md`, the user's shot-by-shot script. One scene of 34 s (the brief allowed up to 35 s), Japanese voice, English subtitles, 16:9, 24 fps, H3 768P delivered at 1080p, GPT Image 2.6 (quality high, reasoning high).

Calls: 3 sheets, 10 keyframes, 8 H3 takes totalling 34 s, 3 voice lines, 1 score, 8 sound effects. Retry allowance: up to 2 retakes per shot. Check current prices on Fal; none are quoted here.

## Creative direction

Quiet restraint. The opening hook is the size of the kneeling machine; the peak is the amber light; the ending is his answer without turning round. One added shot beyond the script: the script's last beat is split into a medium shot for his line and an extreme wide for the title over empty snow, because one framing cannot do both. Every camera is locked.

Style bible: `config/style.md`. Typography: Hiragino Mincho for the title, Arial Bold for subtitles.

## Cast

| Cast id | Character | Outfit | Voice | Run |
|---|---|---|---|---|
| tetsu | Tetsu, 72, retired mechanic | Navy wool cap, grey-blue padded jacket, tan gloves | Bill, stability 0.55 (oldest, driest premade male) | char-tetsu-v1 |

Machine: `char-robot-v1`. Location: `loc-yard-v1`. Full prompts are in `prompts/`.

## Scene breakdown

| Frames | Shot | Camera | Source | Line |
|---|---|---|---|---|
| 0-96 | wide: tiny man on the ladder | locked | H3 | none |
| 96-180 | tag: glove brushes the red tag | locked | H3 | Tomorrow they cut you up. (voice-over) |
| 180-372 | palm: pours, sets the cup down | locked | H3, mouth track | Thirty years… |
| 372-432 | walk: from behind the robot's shoulder | locked | H3 | none |
| 432-504 | cup: tea ripples twice | locked | H3 | none |
| 504-576 | eye: amber light comes on | locked | H3, first and last frame | none |
| 576-708 | face: stops, snorts, answers | locked | H3, mouth track | You're welcome. |
| 708-816 | end: empty snow, title | locked | H3 | none |

Nobody is keyed. No action, and the robot never visibly moves. Full keyframe and H3 prompts: `prompts/fi-s01/02_keyframes.yml`, `prompts/fi-s01/04_shots.yml`.

## Dialogue and score

`prompts/fi-s01/03_dialogue.yml`; score `prompts/fi-s01/03_score.json`, silenced until the amber light by `music_gaps`.

## Review and delivery

Sheets, then voices, score, keyframes, takes, overlay, SFX, grain, each checked before the next. `review:believable`, frame boards, lip-sync check. 
## Change after review

The single `end` take failed on three seeds (a sun flare, then an eye beam twice). The user approved a fix past the allowance of 2 retakes: `end` is now `end-a` and `end-b`, 54 frames each, pinned to three local frames (`end-f0`, `end-f1`, `end-f2`). They were built by hand from `end` and `end-last`, moving only the tiny man, and saved as `output/fi-s01/02_kf_end-f0.png` and so on before `gen:shots`; they are not in `02_keyframes.yml`. The prompt no longer mentions light, and the amber point is drawn in `05_overlay.js` on the locked camera: H3 turns a lit eye into a beam. Limit: up to 2 further attempts at this pair.
