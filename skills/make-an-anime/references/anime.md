# From story to episode

## Breaking the story down

1. **Part → scenes.** Take the requested part of the story (a cold open, an act, a whole episode). Split it into scenes: one place, one continuous time, one dramatic question. Each scene becomes a RUN (`ep01-s01`, `ep01-s02`, …) with its own dialogue, score, keyframes, shots and overlay, all `frames` long at 24fps.
2. **Scene → beats.** Write the beats in order: what changes, who wants what, the line or image that lands it. A 20-second cold open has 5–7 beats; a 1-minute act 12–20.
3. **Beats → shots.** Give every beat a shot (or a held insert). Choose the framing for what the audience must read: establishing wide for place and time, medium for action, close-up for emotion and dialogue, extreme close-up/insert for an object (a screen, a ring, a hand). Cut on motion or on a line; vary shot sizes between consecutive shots; respect the 180° line across a dialogue exchange.
4. **Voiceover and flashes.** A montage film carried by narration plays narration as `vo: true` lines over picture. Brief flashes (1–2 s) are held stills with a p5 push or a short H3 shot.

Shot lengths come from the dialogue: generate the voices first, read the line durations from `03_dialogue_lines.json`, then fix the frame ranges. Leave 6–12 frames of air before a line and after a punchline; never cut a line short. `dialogue:timeline` prints the shots and lines on one timeline, flags a talking shot that does not contain its speaker's whole line or an on-screen line that crosses a cut, and gives the minimum frames each talking shot needs. Run it after every voice change and before `gen:shots`; voice-over may cross cuts.

When a voice is recast or a line rewritten, regenerate only that line (`ONLY=<line> FORCE=1 gen:dialogue`), re-check the timeline (a new take changes the length; `gen:dialogue` refuses a character talking over themself), rebuild the mix, and regenerate the H3 shot of that speaker so the mouth matches the new audio.

## Cast bible and character sheets

For each character **at each age the story needs**: stable id (`hero-adult`, `hero-child`), reference photos if any, apparent age, height/build, face shape, eyes, eyebrows, nose, hair (colour, length, parting, hairline), facial hair, glasses, skin tone, signature outfit plus scene outfits, personality in a pose and three expressions, voice. Photos of a person at a different age are still useful for bone structure and colouring: say in the prompt what to age up or down.

One identity run per character-age: `char-<id>-v1` with `steps: [Steps::RefBase]`, `photos: [references/...]` and `01_ref_base.txt`. The Sunburst edit endpoint receives the photos, so the prompt says "the person in the reference photos" and asks for the sheet layout (see [prompts.md](prompts.md)). Inspect it beside the photos. Likeness is the first acceptance criterion; style consistency with the rest of the cast is the second. A fix is a new version (`-v2`, `edit_from: char-<id>-v1`), never an overwrite.

Recurring locations (the family desk, a bedroom, a school corridor) get location sheets (`loc-<id>-v1`, text-to-image `01_ref_base.txt`, no people), so every shot in that place reuses the same layout, props and light.

## Voices: ElevenLabs Eleven v4

`config/cast.yml` gives each character one voice and its settings, shared by every scene:

```yaml
hero-adult:
  name: Hero (39)
  voice: Brian            # an ElevenLabs voice name or voice ID
  stability: 0.45         # lower = more expressive, higher = steadier
  similarity_boost: 0.8
  ref: char-hero-adult-v1
kid:
  name: Kid (9)
  voice: Jessica
  stability: 0.35
  similarity_boost: 0.75
  ref: char-kid-v1
```

Rules:

- **Every character gets a different voice**, and voices of characters who share scenes must be clearly distinguishable in pitch, age and timbre. Keep the same voice for a character across the whole film; a child who grows up changes voice at a planned age break.
- Children: the premade library has no child voices, so cast young, light, bright voices (Jessica, Lily, Laura, Alice, Charlotte, River) with lower stability, as anime traditionally casts children. Record the casting reasons in the plan.
- Performance lives in the text: audio tags in square brackets (`[sleepy]`, `[whispering]`, `[softly]`, `[laughs]`, `[sighs]`, `[excited]`), punctuation for pauses (`…`, `—`), and short sentences. Tags are performed, not spoken; `review:dialogue` catches a tag that was read aloud.
- Narration (`vo: true`) uses the narrator's voice with a calmer delivery (higher stability, `[warm, reflective]`), is mixed in, and never drives a mouth.
- **Retakes:** the TTS sometimes repeats or adds a word ("Eat… eat, amore"), and its alignment can hide it inside a tag, so trust `review:dialogue` (Whisper `extra`, counted per occurrence, so a doubled phrase fails). Requests are cached by their exact input: `ONLY=<line> FORCE=1` with unchanged text and settings returns the same take (the client logs a warning). For a new take change the tag/punctuation, add or bump the line's `seed:`, or set `NEW_REQUEST=1` (a new paid request). The same holds for every Fal step.
- **Levels:** takes come back anywhere from −30 to −18 LUFS for the same delivery. Measure each `03_line_*.wav` (`ffmpeg -i … -af ebur128 -f null -`) and give an outlier `gain_db:` in `03_dialogue.yml` (e.g. `-5` for an on-screen line 6+ dB hotter than the scene's narration). It levels the take in `03_dialogue.wav` only; mouth tracks keep the raw take, so H3 inputs and the cache are untouched. A plain `gen:dialogue` (cached, free) applies it; then `gen:mix` → `gen:shots` → `gen:overlay FORCE=1` → `sfx:mix`. The mix's `dialogue_db:` stays the scene-wide level.
- Accents: ask for them with a tag (`[light Italian accent]`) only after a test line proves the voice keeps it; otherwise keep the voice's native delivery.

`prompts/<run>/03_dialogue.yml` holds the scene's lines (`name`, `character`, `at` in scene seconds, `text`, optional `vo`, `subtitle` (a gloss shown instead of the text, e.g. "Tutto ok? (All good?)" — not spoken), per-line overrides). `gen:dialogue` writes the placed dialogue, one **mouth track per character** (that character's on-screen lines only) and scene-local word cues for subtitles. A shot whose speaker is on screen uses `audio: <cast id>`, so H3 animates that mouth only while that character talks.

## Score: ElevenLabs Music v2.5

`prompts/<run>/03_score.json` is a composition plan whose chunks follow the beats:

```json
{"chunks": [
  {"text": "[Intro]\n[Instrumental]", "duration_ms": 7000, "positive_styles": ["solo felt piano", "warm analog pad", "night", "intimate anime soundtrack", "sparse"], "negative_styles": ["vocals", "drums"]},
  {"text": "[Build]\n[Instrumental]", "duration_ms": 8000, "positive_styles": ["piano motif returns", "soft music box", "rising strings"], "context_adherence": "high"},
  {"text": "[Swell]\n[Instrumental]", "duration_ms": 4500, "positive_styles": ["strings swell", "suspended chord", "anticipation"], "context_adherence": "high"}
]}
```

Chunks are 3–120 s, at most 30, and must total no more than the scene length; the Music step fits the result to the scene exactly (`music_fade:` seconds of fade, `0` for a hard cut). A plain `03_score.txt` prompt also works. The score is instrumental by default; songs with lyrics need explicit approval. `Steps::Mix` ducks the score under the dialogue (`mix: { music_db:, dialogue_db:, duck:, music_end: }`; `music_end` hard-cuts the score for a smash cut). A supplied soundtrack the user owns can replace the score through `music_from:`.

Check every score's level over time before mixing, not just its peak: scores have come back near-silent for seconds or stopping early, which a single loudness number hides (e.g. `ffmpeg -i output/<run>/03_music.* -af astats=metadata=1:reset=24,ametadata=print:key=lavfi.astats.Overall.RMS_level -f null -`). Ask for "continuous full arrangement to the last second; the final chord rings out" in the last chunk. After a music retake, `gen:mix` rebuilds the stale mix on its own (a mix older than its score or dialogue is not done), and a plain `gen:shots` re-muxes `final.mp4` with it; then re-run `gen:overlay` and `sfx:mix`. The same holds when `music_from:` is added or its shaped file is rebuilt: `gen:music` sees the fit is stale and re-fits locally, without FORCE.

## Sound design

Ambience and spot effects go in `prompts/<sfx-name>/sfx.yml` and are mixed over the finished scene with `sfx:gen` / `sfx:mix`: room tone, night insects, keyboard clicks timed to typing, a door, the whoosh of a cut, a baby's cry. Keep ambience low and continuous across cuts inside a scene; spot effects land on the frame of the action.

## Screens, titles and subtitles

Anything with readable text is drawn in p5, never generated: code editors, terminals, chat windows, dates and place cards ("CITY · 1999"), counters (`HOURS SLEPT: 4 · DAY 3`), title drops and subtitles. `tools/p5/lib/screens.js` provides them: `Anim.codeEditor` (window, tab, gutter, syntax-coloured tokens on a monospace grid, typing with a blinking cursor, eased push toward the cursor, vignette, scanlines, a flash after Enter for a smash cut), `Anim.typing` (deterministic key times, reusable as keyboard SFX cues), `Anim.subtitles` (from `Anim.data("dialogue")`, tags stripped, narration in italics, each cue starting where the voice starts — `speech_at`, measured from the take's leading silence), `Anim.placeCard`, `Anim.vignette`, `Anim.scanlines`, `Anim.mono`. Each frame's `draw` runs inside `push()`/`pop()`, so style set in one frame never leaks into the next; still, set text alignment/font in every helper you write, and check a title at several frames of the full render, not only `anim:preview`. A scene's `05_overlay.js` should mostly choose shots and content, e.g.

```js
const TYPING = Anim.typing("life = Life.new(1987)", { seed: 1987 });
Anim.sketch({
  async load() { this.f = await Anim.fonts({ code: "code.ttf", sub: "sub.ttf", subItalic: "sub-italic.ttf" }); this.shots = Anim.data("shots"); },
  draw(t, frame) {
    const s = this.shots.find((x) => frame >= x.start_frame && frame < x.start_frame + x.frames);
    const local = (frame - s.start_frame) / ANIM.fps, dur = s.frames / ANIM.fps;
    if (s.name === "first-line") Anim.codeEditor(local, dur, { font: this.f.code, tokens: [["life", "#e6edf7"], [" = ", "#ff79c6"], ["Life", "#7fd8ff"], [".new", "#ffd36e"], ["(1987)", "#ffb347"]], typing: TYPING, filename: "life.rb", lang: "Ruby", zoom: [1.1, 1.16] });
    Anim.subtitles(t, Anim.data("dialogue"), { font: this.f.sub, italic: this.f.subItalic });
  },
});
``` Use a `color:` shot (or a `still:` of a blank monitor keyframe) for full-screen inserts and draw the UI over it; `Anim.data("shots")` tells the sketch when each shot starts, `Anim.data("words")` and `Anim.data("dialogue")` give line and word timings.

Held stills (`still:`) and colour inserts (`color:`) are rendered locally; when their `frames`, colour, still or zoom change, a plain `gen:shots` rebuilds them (no FORCE). Hold a place/date card at least ~3 s fully readable (longer text longer), and fade it in on a cut or a musical phrase; a card may cross a cut.

## Continuity

Keep a continuity table in `docs/PROGRESS.md`: per scene, time of day, light direction and colour, outfits, props in hand, screen direction. Reuse the previous shot's keyframe as `base:` when the next shot is the same set-up from a new angle or a moment later, so light and props carry over.
