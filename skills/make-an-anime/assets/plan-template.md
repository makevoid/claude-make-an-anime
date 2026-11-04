# Anime production plan

## Brief and approval scope

Story source, the part being produced (scene/act/episode), target length, language, aspect ratio, 24fps timeline, delivery resolution (H3 768P shots upscaled to 1080p unless stated). Proposed model call counts per model (sheets, keyframes, H3 seconds, voice lines, score seconds, SFX), pricing sources/uncertainty and retry allowance. What approval authorizes, including reference-photo uploads.

## Creative direction

Logline of this part, the opening hook, the emotional peak, the ending/cut-out, recurring motifs planted or paid off. Tone balance (seinen restraint vs shounen energy). Camera language for this part: which moves are used where and why.

Style bible: the exact paragraph in `config/style.md` (`{{STYLE}}`), with palette anchors per light source in hex.

Typography for p5 screens/titles/subtitles: installed font faces and weights, copied to the project's `tools/p5/fonts/` before rendering.

## Research

Link RESEARCH.md: source, verified fact or inspiration, visual treatment, scene.

## Cast bible

| Cast id | Character, age here | Reference photos | Likeness anchors | Outfit here | Voice (ElevenLabs) + settings + casting reason | Identity run |
|---|---|---|---|---|---|---|

For each: the full `01_ref_base.txt` sheet prompt and acceptance criteria (likeness, age, distinctness from siblings, style match).

Locations: id, description, light, full prompt, which scenes use it.

## Scene breakdown

| Run | Frames [start, end) | Beat | Shot | Size/angle | Camera move (from → to, speed, timing) | Source (H3 / still / colour) | Speaker / audio track | Lines (at, text) | p5 (screens, titles, subtitles) | SFX | Dependencies |
|---|---|---|---|---|---|---|---|---|---|---|---|

For every action shot, answer in the plan: is the character painted with the world in one take (never keyed)? If someone runs, is there one runner and a camera that travels, and what passes behind them? For two people talking far apart, use paper-cut panels. See `references/believable-motion.md`.

For every shot: the keyframe prompt and refs, the H3 prompt, the `camera:` block, seconds, audio track, and acceptance (on-model faces, camera did the directed move, mouth on the right lines, no invented text).

## Dialogue and score

`03_dialogue.yml` lines with delivery tags and timings; `03_score.json` chunks aligned to the beats; mix levels and any hard cut.

## Production waves

First 2 pilot assets (usually the protagonist's sheet and one other), then 3–4, 4–8, 6–10 repeatedly. Dependency groups: sheets → voices → score/mix → keyframes → shots → overlay → SFX/VFX → assembly.

## Review and delivery

Likeness board, voice table, `review:believable` with the by-eye list, per-shot playback review, lip-sync check on talking shots, camera check, frame count, soundtrack continuity, SFX levels, delivery paths and known issues.
