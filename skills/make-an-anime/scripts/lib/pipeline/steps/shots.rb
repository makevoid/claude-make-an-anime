module Pipeline
  module Steps
    # Step 4b — a scene's edit (the anime default). prompts/<run>/04_shots.yml lists the shots in edit order, each `frames` long:
    #   image / end_image  keyframe names (Keyframes step), "<run>/<keyframe>", "run:<run>" (that run's sheet/painting) or "ref_base"
    #   prompt             what happens: identity/style ({{STYLE}}), acting beats with timings, mouth, invariants
    #   camera             the camera move, sent to H3 as its own "Camera:" paragraph (see prompts.md "Camera language")
    #   audio: <track>     H3 target audio from this shot's position in the scene: a cast id (that character's mouth track from
    #                      the Dialogue step, silent while others speak), "dialogue" (all lines) or true (the full soundtrack)
    #   seconds            H3 generation length, fractional allowed (0.92..15, >= 2 with audio); default: the shot length
    #   retime: true       the whole H3 clip is squeezed into `frames` (fast camera moves; never with dialogue)
    #   source_frames: N   use only the take's first N frames (cut before a defect, e.g. invented lettering), then trim or
    #                      retime them to `frames`; the downloaded take stays whole, and a retake keeps the same cut point
    #   roll: [from, to]   a virtual camera roll over the shot, in degrees (clockwise), applied to the plate locally; layers
    #                      drawn in p5 follow it with Anim.withRoll(frame, fn) so sprites and background turn together
    #   still: <keyframe>  no generation: the keyframe held (zoom: [1.0, 1.06] for a slow push) — inserts, held drawings
    #   color: "#05070a"   no generation: a solid frame the overlay draws on (screens, title cards, smash-cut white)
    #   from_run: <run>    no generation: that run's video (same timeline) from this shot's position
    #   same_take: <shot>  no generation: the footage of an earlier shot of this list, from skip_frames on, for a beat that must
    #                      repeat exactly (a running gag). Place the repeated line at the same offset inside the shot.
    # The shots are cut, concatenated and muxed with the scene soundtrack (Mix, else Music) -> final.mp4 (the Overlay plate).
    class Shots < ItemsStep
      MODEL = Fal::Models::H3MaxImageToVideo
      FPS = 24
      GEN_SECONDS = 5 # default H3 length per shot (its minimum; max 15)

      def specs
        @specs ||= begin
          at = 0
          shots = yaml("04_shots")
          raise ArgumentError, "Shot frames must sum to section frames" unless shots.sum { |shot| shot.fetch("frames") } == (project.duration * FPS).round
          shots.to_h do |shot|
            spec = shot.merge("start_frame" => at)
            at += shot.fetch("frames")
            [shot.fetch("name"), spec]
          end
        end
      end

      # Held stills and colour inserts are rendered locally for free, so a cached one is rebuilt whenever its spec
      # changes (frames, colour, still, zoom) — no FORCE needed. A white card once kept its old 12 frames after its
      # frames were raised to 96 because a cached local shot counted as done. Items from before this record no spec:
      # those are compared by frame count only.
      def run!(**)
        Believability.refuse!(specs.flat_map { |name, spec| Believability.shot_problems(name, spec) })
        super
      end

      def stale_item?(name, spec, item)
        return false unless spec["still"] || spec["color"]
        stale = item["spec"] ? item["spec"] != local_spec(spec) : ffmpeg.summary(item["path"]).dig(:video, :frames).to_i != spec["frames"]
        warn "[#{key}] #{name}: local shot spec changed -> rebuilding" if stale
        stale
      end

      def local_spec(spec) = spec.slice("frames", "color", "still", "zoom")

      def generate(name, spec)
        if (run = spec["from_run"])
          return { source: run, path: Project.new(run).fetch!(:video, :path) }
        end
        if (take = spec["same_take"])
          raise ArgumentError, "shot #{name}: same_take #{take} is not an earlier generated shot" unless reusable_take?(name, take)
          return { source: take, path: project.path("04_shot_#{take}.mp4") }
        end
        if spec["still"] || spec["color"]
          image = spec["still"] && keyframe_path(spec["still"])
          out = ffmpeg.still_video(project.path("04_shot_#{name}.mp4"), frames: spec["frames"], fps: FPS, image: image,
                                   color: spec.fetch("color", "#000000"), zoom: spec["zoom"])
          return { source: spec["still"] || spec["color"], path: out, spec: local_spec(spec) }
        end
        raise ArgumentError, "Never retime a talking or singing shot" if spec["audio"] && spec["retime"]
        seconds = spec.fetch("seconds") { default_seconds(spec) }
        raise ArgumentError, "shot #{name} needs more source frames (#{spec["frames"]} > #{seconds}s)" if !spec["retime"] && spec["frames"] > seconds * FPS
        raise ArgumentError, "shot #{name}: source_frames #{spec["source_frames"]} < frames #{spec["frames"]} needs retime: true" if spec["source_frames"] && !spec["retime"] && spec["source_frames"] < spec["frames"]
        audio = audio_url(name, spec, seconds) if spec["audio"]
        result = MODEL.new(client: client).animate(
          prompt: self.class.h3_prompt(project, spec), image_url: keyframe_url(spec.fetch("image")),
          end_image_url: spec["end_image"]&.then { |k| keyframe_url(k) }, target_audio_url: audio,
          duration: seconds, seed: seed, resolution: ENV.fetch("VIDEO_RES", MODEL::DEFAULT_RES)
        )
        url = result.output.fetch("video")["url"]
        { request_id: result.request_id, input: result.input, url: url, path: download(url, "04_shot_#{name}.mp4") }
      end

      # The H3 prompt: the shot prompt ({{STYLE}} expanded), then the camera direction as its own paragraph.
      def self.h3_prompt(project, spec)
        text = project.expand(spec.fetch("prompt")).strip
        camera = spec["camera"]
        camera = camera.map { |k, v| "#{k}: #{v}" }.join("; ") if camera.is_a?(Hash)
        camera ? "#{text}\n\nCamera: #{project.expand(camera).strip}" : text
      end

      def finish(items)
        segments = specs.map do |name, spec|
          { path: items[name]["path"], frames: spec["frames"], retime: spec["retime"], keep: spec["source_frames"],
            skip: source_skip(spec), roll: spec["roll"] }
        end
        plate = ffmpeg.concat_shots(segments, project.path("04_plate.mp4"), fps: FPS, w: 1920, h: 1080) # 768P H3 shots upscaled to the 1080p delivery
        { path: ffmpeg.mux(plate, project.soundtrack, project.path("final.mp4"), shortest: false), plate: plate }
      end

      def review
        final = project[key]["path"]
        summary = ffmpeg.summary(final)
        frames = summary.dig(:video, :frames)
        want = specs.values.sum { |s| s["frames"] }
        cuts = specs.flat_map do |name, s|
          [[s["start_frame"], "#{name} first"], [s["start_frame"] + s["frames"] - 1, "#{name} last"]].map do |n, label|
            [ffmpeg.frame_index(final, n, project.review_path(key, "f#{n}.jpg")), "f#{n} #{label}"]
          end
        end
        # Frames each source must have: from_run and same_take sources start part way in, generated ones at 0.
        short = specs.reject do |name, s|
          s["retime"] || s["still"] || s["color"] || ffmpeg.summary(project[key]["items"][name]["path"]).dig(:video, :frames).to_i >= source_skip(s) + s["frames"]
        end
        {
          summary: summary, contact_sheet: ffmpeg.contact_sheet(final, project.review_path(key, "contact_sheet.jpg"), cols: 6, rows: 3),
          cuts: magick.board(cuts, project.review_path(key, "cuts.jpg"), tile: "2x", width: 640),
          **verdict(
            "frames = shots total" => [frames == want, "#{frames}/#{want}"],
            "duration ~#{project.duration}s" => [(summary[:duration] - project.duration).abs < 0.1, "#{summary[:duration]}s"],
            "master audio muxed" => [summary.dig(:audio, :codec) == "aac", summary[:audio].inspect],
            "every shot long enough" => [short.empty?, short.empty? ? "ok" : "too short: #{short.keys.join(", ")}"]
          )
        }
      end

      protected

      def endpoint = MODEL.endpoint

      private

      def source_skip(spec)
        return spec["start_frame"] if spec["from_run"]

        spec.fetch("skip_frames", 0)
      end

      def reusable_take?(name, take)
        names = specs.keys
        source = specs[take]
        source && names.index(take) < names.index(name) && !source["still"] && !source["color"] && !source["from_run"] && !source["same_take"]
      end

      # The shot's own length (H3 may add ~0.7 s), at least 2 s when audio is pinned, rounded up to 0.1 s.
      def default_seconds(spec)
        [(spec["frames"].fdiv(FPS) * 10).ceil / 10.0, spec["audio"] ? 2.0 : 1.0].max
      end

      def keyframe_path(name)
        return project.fetch!(:ref_base, :path) if name == "ref_base"
        return Project.new(name.delete_prefix("run:")).fetch!(:ref_base, :path) if name.start_with?("run:")
        project.keyframe(name)["path"]
      end

      def audio_url(name, spec, seconds)
        from = spec["start_frame"].fdiv(FPS)
        return song_url(name, from, seconds) if spec["audio"] == true
        voice_url(name, spec["audio"], from, seconds)
      end
    end
  end
end
