# Plan: Too Salty

## Brief and approval scope

The user's script, `docs/BRIEF.md`, is the source. About 70 s (73.5 s as cut), 24 fps, 16:9, 768P H3 upscaled to 1080p, Japanese voices, English subtitles. The user asked for it to be generated.

| Model | First pass | Retake ceiling |
| --- | --- | --- |
| GPT Image 2.6 (quality high, reasoning high) | 2 character + 2 location sheets, about 18 keyframes | 10 more |
| MiniMax H3 Max 768P | about 18 takes | 10 more |
| ElevenLabs Eleven v4 | 6 voice tests, 13 lines | 10 more |
| ElevenLabs Music v2.5 | 1 score | 1 more |
| Stable Audio SFX | about 9 sounds | 6 more |
| Whisper | line checks | as needed |

## Creative direction

Quiet, warm, dry. The opening hook is the routine; the peak is the silence and the hand on the pan; the payoff is the third "too salty". No green screen, no pasted-on effects, no moving sprites: every shot is one painted H3 take. Locked or very slow cameras throughout, because this is an observational film.

Typography: subtitles in Arial Bold, Japanese cards and the title in Hiragino Mincho ProN.

## Geography

Counter across the room. Kiku on the stool on the near side, Hana behind it at the stove. Kiku is always screen left facing right, Hana screen right facing left, or with her back to us at the stove. The camera stays on one side of that line.

Script notes carried into production: the salt container stays closed and visible; Kiku's chopstick click recurs; rain on tin and the copper pan share a metallic sound. Shot 5 reuses the footage and voice of shot 3, so "identical to before" is literal.

## Cast

| Id | Character | Voice | Identity run |
| --- | --- | --- | --- |
| hana | Hana Mori, 19, apprentice | Jessica | char-hana-v1 |
| kiku | Kiku Mori, 74, owner | from the voice test | char-kiku-v1 |

Locations: `loc-shop-v1` (interior) and `loc-street-v1` (exterior, relit for dawn).

## Order of work

1. Sheets, then Kiku's voice test.
2. Voices, which fix the timing.
3. Test the shots the story depends on: the silence, two faces with a hand on the pan, the final bite.
4. Everything else, score, sound, grain, delivery.

## Action check

Nobody runs, falls or fights. No shot is keyed. `review:believable` runs after the prompts and after the takes.

## Risks

Hands and chopsticks, Kiku's age in the voice, two faces and one hand, lip-sync while chewing. Fallbacks are in the script.
