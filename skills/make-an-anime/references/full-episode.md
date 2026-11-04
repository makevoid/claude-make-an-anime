# Full episodes

The toolkit was first used on a narrated anime documentary of over 12 minutes, about 40 scenes long. This is what a project of that size needs beyond the single-scene workflow.

## Structure

- `ruby mv.rb 'scene:new[ep01-s05,480]'` scaffolds a scene: `config/generations/ep01-s05.rb`, prompts and a score skeleton. One file per scene, so several agents can add scenes without editing a shared file. A run defined twice is an error.
- `config/episodes/ep01.yml` is the playing order. Scene numbers are stable ids, so a scene can move or be added without renumbering.
- Order of work: sheets and voices first, then the opening and the emotional peak, so the look and the budget are proven early. Then production waves (`work:next`, see [production.md](production.md)).

## Commands per scene

```sh
RUN=ep01-s05 ruby mv.rb gen:dialogue        # paid: one take per line
RUN=ep01-s05 ruby mv.rb review:dialogue     # paid: Whisper check of every line
RUN=ep01-s05 ruby mv.rb dialogue:timeline   # local: lines against shots and cuts
RUN=ep01-s05 ruby mv.rb gen:music           # paid
RUN=ep01-s05 ruby mv.rb gen:mix             # local
RUN=ep01-s05 ruby mv.rb gen:keyframes       # paid
RUN=ep01-s05 ruby mv.rb gen:shots           # paid
RUN=ep01-s05 ruby mv.rb review:camera       # local: measured against directed camera, with frame strips
RUN=ep01-s05 ruby mv.rb gen:overlay         # local for anime scenes
SFX=ep01-s05-sfx ruby mv.rb sfx:gen         # paid, cached
SFX=ep01-s05-sfx ruby mv.rb sfx:mix         # local
```

Retakes: `ONLY=<item> FORCE=1` on keyframes, shots or dialogue. Replaced items go to `output/<run>/rejected/`.

## Joining and levelling

```sh
SEAMS=1 VOICE_DB=-24 ruby mv.rb 'episode:preview[output/ep01-preview.mp4,ep01]'
ruby mv.rb 'audio:seams[output/ep01-preview.mp4,ep01]'
```

- Scenes are mixed one at a time, so their loudness drifts. Level on the voice (`VOICE_DB`), not only on the whole mix, or a loud fight scene takes its narrator line far below the others. `LUFS` sets a whole-mix target instead.
- `SEAMS=1` fades each scene out across the air after its last line and in across the air before its first. A scene that opens on a hit keeps it with a very short fade. Silent cards are left alone.
- `audio:seams` reports both ways music can change abruptly: at a join between scenes (`cut` if the last 30 ms still sound, `hard_start` if the first 30 ms are loud), and at a chunk boundary inside a scene's score.

## Voice over the bed, and air before a cut

- `mix: { voice_lift_db: N }` raises the voice and also writes `03_mix_ref.wav` without the lift. With `voice_dip_db: 6` in `sfx.yml`, `sfx:mix` reads cue levels from that reference and dips the cues under speech, so a louder voice does not bring the effects up with it.
- Hold the last shot so a line ends at least 0.5 s before the cut. A held score needs `scene:tail[run,source,seconds]` and `music_from`. `scene:reaudio[run]` puts a new mix on `final_overlay.mp4` without re-rendering the picture.
- A sound shorter than its cue stops early with no warning. Check cue `len` against the sound's real duration, and repeat the sound to carry a long cue.
- An open mouth with no voice needs a sound (a laugh, a breath, a murmur), or the shot needs fixing.

## Lines that aren't plain speech

Optional keys on a dialogue line: `gate_s` silences the head of a take in the mix, for a blip before the first word; `keep_s` keeps only that much of a take; `inner: true` with `vo: true` is a thought, high-passed with a short room behind it; `subtitle: " "` is a laugh or breath with no caption. Thoughts and blank-subtitle lines do not count as speech when a scene is levelled.

## Score shaping

`tools/python/score_tool.py` makes small local edits without a new generation: `crossfade IN OUT T L` holds the last chord before a hard change and fades it into the new section; `soften IN OUT T L in|out` softens an abrupt start or stop; `insert`, `remove`, `freeze` and `length` retime it to the picture. Point `music_from` at the result. Keep a change that is timed to the picture.

## Whole-film VFX

VFX beats live in `prompts/ep01-vfx/beats.yml` in scene frames. `scene:vfx[ep01-vfx]` turns them into film frames in `cues.yml`; rerun it after any scene changes length, join, then `vfx:render`.

## Limits of H3

- H3 may insert a hard cut inside one shot, and automatic detection does not separate it from character motion. Write "ONE CONTINUOUS TAKE with no cuts" and read the `review:camera` strips by eye.
- One named camera move per shot, with its end framing stated. Compound moves drift.
- Set a retake ceiling per scene and report what remains imperfect. A retake that fixes one thing often breaks another.
