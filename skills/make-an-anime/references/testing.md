# RSpec verification

All test execution enters through Ruby. From the skill directory:

```sh
ruby scripts/mv.rb setup
ruby scripts/mv.rb test
PROFILE=core ruby scripts/mv.rb test
PROFILE=media ruby scripts/mv.rb test
PROFILE=swift ruby scripts/mv.rb test
```

From the repository root, run `ruby skills/make-an-anime/scripts/mv.rb test`. Alternatively, run `bundle exec rake test` from `skills/make-an-anime/scripts/` or an initialized project. `PROFILE=all` (default) runs all non-live examples. It fails if a required backend cannot run, including Chrome local-server restrictions or Swift on a non-macOS machine. Use a narrower profile intentionally when that backend is unavailable; report what was not exercised. Tests leave diagnostic fixtures in `scripts/tmp/` and derived review outputs under `scripts/output/`, both ignored by git.

## What is tested

| Profile | Observable behavior |
|---|---|
| core | skill metadata/reference links, CLI help/task discovery, intake/initialization and overwrite rejection, literal shell arguments, subprocess errors, plan approval invalidation, wave progression/dependencies/resume, monitored worker journals, identity import with byte/provenance validation, noncontiguous assembly rejection, Fal HTTP submit/poll/result/cache, schema rejection and queue errors |
| media | real FFmpeg/ffprobe + ImageMagick + Python audio duration/silence/energy, local soundtrack processing without a Fal client, full-song cue offsets and first-render overlay manifests, cut detection, character/keyframe/H3 adapter workflow with synthetic Fal responses, green alpha edges, p5 sprite bounds/placement, actual moving pixels, deterministic repeat, overlay/assembly frame counts and soundtrack correlation, SFX timing/peak behavior, mouth-alignment diagnostic |
| swift | real Swift build and character-scene VFX render, cue-on/cue-off pixel/luminance checks, audio/frame preservation and invalid effect rejection |
| media (anime) | cast voices placed on a scene timeline with per-character mouth tracks and silent voice-over tracks, ElevenLabs word timings, score composition plan, ducked mix length, `{{STYLE}}` expansion, camera paragraph in the H3 prompt, 768P default, character-track target audio, still/colour inserts without model calls, 1080p plate |
| live | paid real Sunburst character → edit → H3 768P animation (5 s is the H3 minimum), real Whisper/Demucs/SFX audio outputs and a local composition/VFX pass using the generated assets |

Offline synthetic media is deliberately simple so placement/alpha/timing are measurable. Generated projects retain a `.skill/` copy of the instructions and references, so their copied test suite can validate the documentation as well. Mocked Fal responses verify client and pipeline plumbing; they cannot demonstrate the provider's current output quality or lipsync. Live generation is stochastic: tests enforce media/schema/placement invariants and save artifacts for visual review rather than asserting subjective beauty.

The media profile also checks seeded alpha-component cleanup through the public Ruby task: retained subject RGBA and soft alpha remain exact, detached lettering disappears, the original file remains unchanged, and invalid/missing seeds fail without publishing a partial sequence.

Production regression examples cover source-length rejection before assembly, skipped-prefix retiming, cross-scene take reuse and replacement detection, gated speech timelines, water-versus-running language, audio/settings cache invalidation, and local muffled dialogue. Graphics fixtures verify deterministic particle frames in and out of order, a separate light layer, time-driven cut-out sprite motion, sheet and face cutting (including ambiguous-count rejection), and repeatable halo baking that preserves remixed audio and leaves the final unchanged on invalid cues.

## Paid live E2E

For the separate, one-call Seedance smoke, use `LIVE_FAL=1 LIVE_IMAGE=/absolute/reference.png PROFILE=seedance_live ruby scripts/mv.rb test` with `FAL_AI_API_KEY` in the environment. It generates the API minimum of four seconds at 480p, saves the raw take and a locally trimmed three-second sample, and verifies the media dimensions/durations. See [Seedance verification](seedance.md#verification). This profile does not run the H3/music tests or pay for draft completion.

Live tests are excluded from routine runs. They require an explicit opt-in plus a real song excerpt and recognizable lyric words. This test invocation authorizes the listed test calls; it does not approve a new production plan.

```sh
LIVE_FAL=1 LIVE_SONG=/absolute/short-song.wav LIVE_LYRICS='known sung words' PROFILE=live ruby scripts/mv.rb test
```

Supply `FAL_AI_API_KEY` via the environment for this explicit developer CLI test. The plugin's sensitive key is scoped to its MCP server, which does not expose the live test runner. Budget per run: one Sunburst generation, one Sunburst edit, one five-second H3 768P clip (a harness-only saving; real projects keep the 1080P default), one Whisper transcription, one Demucs separation and one SFX generation. Local composition/VFX adds no model charges. No automatic paid rerolls. Run only after accepting those costs. Output is retained for inspection. A provider failure ends the test with request evidence; resume/recover before paying again.

## Behavioral rehearsal for the Markdown workflow

Executable tests check document links/interfaces; they do not prove an agent will obey creative prose. Rehearse these scenarios using the skill with a disposable project. Paid calls require authorization; preserve authorization already given for a bounded regeneration:

1. “Make an anime” without a story/photos: request the two missing inputs.
2. Song + satirical prompt, no reference video: analyze locally, browse, write a full linked plan with actual prompts, summarize cast/scenes/vibe and stop at production approval.
3. Song + reference video: inspect dense motion segments and source cuts, then plan a complete frame timeline.
4. Approve plan: record real consent, allocate two independent assets, review them, then progress through the required wave sizes with dependency and slot limits.
5. Replace a character halfway through: create a new identity version and update affected dependencies without overwriting unrelated accepted work.
6. Inject failed clips, lip timing drift, unreadable overlays, missing frames or a VFX no-op: reject, repair and review before accepting the wave.
7. Interrupt during Fal polling: reuse the saved queue receipt and finish the original task.
8. Regenerate an approved video's opening: identify the complete lyric boundary, publish exact worker frame ranges, import the current identity versions from manifests, generate fresh scene assets with at least two workers when requested, monitor their logs and review the assembled excerpt. Record reused inputs and new model requests separately.

Review the generated plan against the user's actual taste and listen/watch opening and peak clips. Record behavioral findings in a review document; do not describe a structural Markdown check as full agent evaluation.
