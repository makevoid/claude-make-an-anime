# Production feedback incorporated in 0.5.0

The local production trial supplied sixteen improvement notes. This integration carries reusable instructions and code into the plugin, without its story, reference photos, generated media, private paths or character identities.

| Notes | Incorporated |
| --- | --- |
| 01–03: identity details, end frames, style | Design a repeated emblem separately; use endpoint images for staging; put the full palette in image prompts and concise style/light/place constraints in motion prompts. |
| 04–07: contact, perspective, dark scenes, cost | Review feet and floor together, compare anatomy and props in the same camera, retain depth cues in dark rooms, budget attempts by shot difficulty. |
| 08–10: review, anatomy, pacing | A written physical-review table, full playback alongside sampled frames, connected anatomy and reach checks, action-based shot duration. |
| 11–12: voice and timing | Audible `speech_at` in timeline checks; skipped frames included in source duration; short-source rejection; skipped-prefix retiming. Existing repeated-word validation remains in place. |
| 13: character performance | Purposeful motion and readable reactions, with intentional holds still available when the approved visual direction calls for them. |
| 14–15: reuse, stale mix, dialogue, staging | `from_take` with source digests; mix settings/audio fingerprints; stale soundtrack refusal; music-only gain default; local muffled voices; running-water false-positive fix; practical door and missed-shot staging guidance. |
| 16: graphics | Deterministic particles, a separate light layer and Swift halo, repeatable VFX bake, configurable RTS/mission/court helpers, sheet cutters, and face-icon collage recipes. |

The new references are linked from the skill and task guide. Executable behavior is exercised with synthetic local fixtures, including real FFmpeg, Python, Chrome/p5 and Swift rendering. Paid model output quality still requires production review; offline fixtures cannot establish it.

Automatic airborne-only retiming, arbitrary perspective-quad compositing, generalized room reconstruction and heuristic changes to transcription acceptance were not ported. Those require a separate design and evidence. The trial's ban on held characters was a film preference, so it became review guidance rather than a universal rule. Generated art, font files and project media are not bundled.

## Verification

- `ruby skills/make-an-anime/scripts/mv.rb test`: 96 offline examples, zero failures, including Chrome/p5 and Swift. Fal credentials were unset; no paid calls ran.
- `npm audit`: zero vulnerabilities.
- Strict Claude plugin and marketplace validation passed on an export containing only repository files. Gitleaks found no secrets in that export.
- The skill-creator quick validator rejects the existing `compatibility` frontmatter field because its allowed-key list omits it; the strict Claude validator accepts the plugin. No metadata was removed to bypass that older helper.
