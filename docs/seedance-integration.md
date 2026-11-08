# Seedance integration

## Behavior

MiniMax H3 remains the default at 768P. Seedance 2.5 US is an explicit selection and defaults to 480p. Native Seedance requests are rounded up to whole seconds with a four-second minimum and a 30-second maximum; the edit keeps its requested frame count. Draft completion is explicitly selected and only supports 1080p.

See the maintained [usage reference](../skills/make-an-anime/references/seedance.md) for YAML, scene/environment precedence, reference audio, drafts and commands.

## Architecture and implementation

- `Fal::Models::SeedanceImageToVideo`, `SeedanceReferenceToVideo` and `SeedanceDraftComplete` wrap the three requested queue endpoints. They share the existing approval, receipt cache and download client. OpenAPI discovery includes all three.
- `Pipeline::VideoGeneration` translates provider-specific inputs for `Shots`, `Clips` and `Video`. H3 keeps target audio and pinned end frames. Seedance reference mode receives audio references and explicitly rejects pinned end frames; image mode rejects unsupported seeds. No implicit provider fallback or draft completion occurs.
- Item manifests retain endpoint, request ID, exact input, returned seed and draft ID. Drafts can be completed in the existing shot workflow, preserving archived takes, or through `seedance:complete[input.json,out.mp4]` with a standalone manifest. The credential-scoped MCP task interface supports provider selection and completion.
- `seedance_live` is a separate paid test profile for one four-second 480p request, a three-second local trim, a contact sheet, queue receipts and probe evidence. It does not run other paid tests or retry with fresh inputs.

## Validation status — 2026-11-08

The three current Fal OpenAPI schemas were fetched and inspected. Core regressions cover default H3 behavior, explicit provider/resolution selection, string durations, reference audio mapping, rejected unsupported combinations, completion payloads, single-video routing and standalone completion receipts. The media regression assembles a simulated four-second Seedance source into an exact three-second, 72-frame edit.

The full offline suite passed: **111 examples, 0 failures**, including real FFmpeg, Python, p5 and Swift checks. After the live result exposed dimension rounding, the focused core suite passed **67 examples, 0 failures**, including the added rounding regression. Logs are `work/seedance-test.log` and `work/seedance-core-test.log`. Markdown reference checks and `git diff --check` also pass.

The user supplied an existing credential-file path for this session; its value was injected only into the child process environment. The live smoke **passed** with one paid image-to-video request: `01a1ba60-aa91-79b1-bcda-5c785e562eed`. Requested settings were four seconds, 480p, H.264, no generated audio. The returned clip is 4.042 seconds, 856×478, 24 fps, 97 frames. The locally trimmed sample is exactly three seconds and 72 frames. Its contact sheet was inspected: the snowy scene, person and robot remain recognizable across the sample with camera/motion changes. This is API/media and sampled-frame verification, not a lip-sync or full creative-quality evaluation.

The provider's nominal 480p tier rounded the dimensions to 856×478. The initial exact-height assertion caught this; the test and video review now allow up to eight pixels of tier rounding. Re-running the test reused the same completed queue receipt, making no additional paid generation. The live log is `work/seedance-live-test.log`; video, contact sheet, provider response and probe evidence are in `skills/make-an-anime/scripts/tmp/seedance-live/`. Live reference-to-video and draft completion remain unverified; their routing and payloads have offline coverage.

The repository's Markdown metadata/link tests pass. The generic Codex skill validator rejects the pre-existing Claude skill `compatibility` frontmatter field; this integration preserves that existing field.
