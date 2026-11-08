# Seedance 2.5 US

Use Seedance only when the user explicitly requests it. Otherwise use MiniMax H3 Max at its existing 768P default. Seedance generation defaults to 480p; do not copy Fal's 720p default. Both providers use the existing Fal queue, approval, receipts, downloads and manifests.

## Select the provider

Set `model: seedance` on a shot in `04_shots.yml` or a clip in `04_clips.yml`:

```yaml
- name: breeze
  model: seedance
  image: rooftop
  frames: 72
  seconds: 3
  prompt: A gentle breeze moves her hair. Keep the same character and painted setting.
  camera: slow dolly-in
  # resolution: 720p   # only when requested; default is 480p
  # end_image: rooftop_end
```

Seedance accepts 4–30 whole seconds encoded as strings. The toolkit rounds up fractional durations and uses at least four seconds; the shot edit still uses the exact `frames` requested. A three-second shot requests a four-second source and trims it to 72 frames. Durations over 30 seconds fail rather than silently truncating. Do not retime dialogue. `gen:shots` still assembles the finished plate at 1080p; that local upscale does not change the provider's native resolution.

Fal's resolution tiers may round dimensions slightly: the verified 480p sample returned 856×478. Review checks allow eight pixels of rounding while retaining the requested tier in the manifest.

For a whole scene, add `video: { model: "seedance" }` to its `scene(...)` configuration. Alternatively, use `VIDEO_MODEL=seedance` with `gen:shots`, `gen:clips` or `gen:video`. Selection precedence is per-item `model`, scene `video.model`, `VIDEO_MODEL`, then MiniMax. Resolution precedence is per-item `resolution`, scene `video.resolution`, `VIDEO_RES`, then the provider default. Use `model: minimax` (or `h3`) for an explicit H3 override.

Cached paid takes keep the existing reuse behavior. After editing provider/settings, use `ONLY=breeze FORCE=1` to replace an existing take. The previous take is archived; identical inputs resume the existing queue receipt instead of charging again.

## Image, reference media and audio

The [image-to-video API](https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=bytedance/seedance-2.5/us/image-to-video) supports a starting `image`, optional pinned `end_image`, and only `aspect_ratio: auto`. It has no input seed and no target-audio field. Do not set `SEED` for this mode; use reference mode if you need a seed.

The [reference-to-video API](https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=bytedance/seedance-2.5/us/reference-to-video) is selected by `mode: reference`, reference URL arrays, or a shot's `audio:` track. It accepts:

```yaml
- name: response
  model: seedance
  mode: reference
  image: hero_closeup
  frames: 96
  audio: hero
  prompt: "The person in @Image1 speaks softly, with restrained expression."
  camera: locked close-up
  # image_urls: [https://.../character.png, https://.../location.png]
  # video_urls: [https://.../motion.mp4]
  # audio_urls: [https://.../ambience.wav]
  # aspect_ratio: "16:9"
```

`image_urls` replaces the single keyframe reference when supplied. `video_urls` and `audio_urls` add hosted references; local files can be uploaded with `media:upload`. Address references in the prompt as `@Image1`, `@Video1`, `@Audio1`, etc. `audio:` cuts/uploads the existing character mouth track and appends it to `audio_urls`; the toolkit adds a prompt identifying that audio reference. This guides performance and is not H3's pinned `target_audio_url` or a guarantee of lip-sync. Review mouth timing; the final edit still uses the clean scene soundtrack.

Reference mode cannot pin an end frame; combining it with `end_image` fails. `gen:video` uses reference mode because that step always supplies the song, and omits its H3-only automatic end-frame pin. Image-only Seedance generation defaults to `generate_audio: false`; a supplied mouth track enables audio generation unless explicitly overridden. You can request `generate_audio: true` for native generated sound, but `gen:shots` replaces it with the scene mix in the final edit. The raw take retains the generated sound.

Limits: up to 30 images, 10 videos and 10 audio files, 50 files total. Reference audio is MP3/WAV, 1.8–30.2 seconds each, at most 15 MB each and 30.2 seconds combined. Videos are MP4/MOV, 1.8–30.2 seconds each, at most 200 MB each and 30.2 seconds combined. Fal enforces file-content limits. Reference `task` supports `reference` (default), `auto`, `editing` and `extension`; editing lets the provider choose duration and aspect ratio, so inspect the returned duration before planning an exact edit.

## Draft preview and completion

Add `draft: true` to an image or reference shot at 480p. The item manifest saves its `draft_id`, request, endpoint, input and returned seed. A regular 480p take is not automatically a draft. Inspect the draft before choosing to complete it.

The [draft completion API](https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=bytedance/seedance-2.5/us/draft/complete) only produces 1080p. US draft IDs expire after seven days and must be completed by the original caller. There is no automatic completion or paid upscale.

To replace a draft shot, copy its saved ID into that shot as `draft_id: <saved-id>`, keep `model: seedance`, `frames`, and any trim settings, then run `ONLY=breeze FORCE=1 ... gen:shots`. Completion sends only the draft ID and completion settings; it does not regenerate the prompt. The old draft is archived. Remove `draft_id` when you intend to generate a new take.

For a standalone completion, write `complete.json`:

```json
{"draft_id": "the saved draft_id"}
```

Run through the approved project's Ruby CLI or the anime MCP `run_task`:

```sh
ruby mv.rb 'seedance:complete[complete.json,output/completed.mp4]'
```

This stores the video and `output/completed.mp4.json` with the completion receipt. Completion always uses 1080p, independently of `VIDEO_RES`. The ordinary generation default remains 480p.

## Verification

`openapi:fetch` includes all three Seedance endpoints. The offline core/media tests cover routing, default and explicit resolution, duration conversion, reference-audio mapping, draft metadata/completion and a three-second assembled shot.

The separate live smoke makes one paid four-second image-to-video request and trims a three-second sample:

```sh
LIVE_FAL=1 LIVE_IMAGE=/absolute/reference.png PROFILE=seedance_live ruby scripts/mv.rb test
```

Provide `FAL_AI_API_KEY` in the environment. Results, the queue receipt, input/output, a contact sheet and probe evidence stay in `scripts/tmp/seedance-live/`. Repeating unchanged inputs reuses the receipt. This smoke does not pay for reference-to-video or draft completion and does not prove their live behavior.
