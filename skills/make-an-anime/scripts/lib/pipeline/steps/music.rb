module Pipeline
  module Steps
    # Step 3 — the sung hook (minimax/music-3), fitted to exactly project.duration seconds
    # and re-uploaded so the video step and the final mux use the same audio.
    # Generations with `import: { music: "run1" }` reuse that run's song instead, and
    # `music_from: <file>` cuts it from a local video/audio file (run4: the reference clip's song); with
    # `music_offset: <seconds>` only project.duration seconds from there (one section of a longer song).
    class Music < Step
      MODEL = Fal::Models::Music3

      # A fit whose source changed is stale and is re-fitted without FORCE: music_from added, removed or pointed
      # elsewhere after gen:music ran, or the shaped file rebuilt after the fit (a raw take once shipped because
      # music_from was set after the first gen:music). Mix then sees a newer score and rebuilds too.
      def done? = super && !stale?

      def stale?
        return false if project.import_source(key)

        rec = project[key]
        why = if rec["endpoint"] != endpoint then "source #{rec["endpoint"]} -> #{endpoint}"
              elsif source_file && File.exist?(source_file) && File.mtime(source_file) > File.mtime(rec["path"])
                "#{source_file} newer than the fit"
              end
        warn "[#{key}] stale: #{why} -> refitting" if why
        !why.nil?
      end

      # Anime score: prompts/<run>/03_score.json ({ "chunks": [...] } composition plan) or 03_score.txt (a prompt) uses
      # ElevenLabs Music v2.5, instrumental, scene length. Generation option music_fade: seconds of fade-out (default 0.4).
      def submit
        return extract(source_file) if source_file
        return score if project.prompt?("03_score")

        MODEL.new(client: client).compose(
          prompt: project.prompt("03_music_prompt"),
          lyrics: project.prompt("03_music_lyrics"),
          duration: project.duration, seed: seed
        )
      end

      def materialize(result)
        audio = result.output.fetch("audio")
        raw = if audio["path"]
                offset = project.generation[:music_offset]
                ffmpeg.extract_audio(audio["path"], project.path("03_music_raw.wav"), from: offset || 0, seconds: offset && project.duration)
              else
                download(audio["url"], "03_music_raw#{ext(audio["url"])}")
              end
        # A section of a longer song (music_offset) is not faded, so sections join back into the original track.
        fade = project.generation[:music_offset] ? 0 : project.generation.fetch(:music_fade, 0.4)
        fitted = ffmpeg.fit_audio(raw, project.path(format("03_music_%gs.wav", project.duration)), seconds: project.duration, fade: fade)
        base_data(result).merge(
          raw_url: audio["url"], raw_path: raw, model_duration: result.output["duration"], seed: result.output["seed"],
          path: fitted, url: project.generation.fetch(:upload_music, true) ? client.upload(fitted) : nil
        )
      end

      def review
        raw, fitted = project[key]["raw_path"], project[key]["path"]
        wav = ffmpeg.to_wav(raw, project.review_path(key, "raw.wav"))
        energy = python.audio_energy(wav)
        loud = energy["windows"].select { |w| w["rms_db"] > -30 }
        vocal = energy["windows"].select { |w| w["rms_db"] > -30 && w["vocal_ratio"] > 0.35 }
        transcript = transcribe
        words = transcript[:text].downcase.scan(/[a-z']+/)
        expected = project.generation.fetch(:lyrics, [])
        {
          transcript: transcript,
          raw: ffmpeg.summary(raw), fitted: ffmpeg.summary(fitted),
          waveform: ffmpeg.waveform(raw, project.review_path(key, "waveform.png")),
          spectrogram: ffmpeg.spectrogram(raw, project.review_path(key, "spectrogram.png")),
          energy_timeline: energy["windows"].map { |w| "#{w["t"]}s #{w["rms_db"]}dB v#{w["vocal_ratio"]}" },
          **verdict(
            "raw length ~#{project.duration}s" => [(energy["duration"] - project.duration).abs <= 2.5, "#{energy["duration"]}s raw"],
            "fitted exactly #{project.duration}s" => [(ffmpeg.duration(fitted) - project.duration).abs < 0.1, "#{ffmpeg.duration(fitted).round(2)}s"],
            "not silent" => [loud.size >= energy["windows"].size * 0.6, "#{loud.size}/#{energy["windows"].size} windows > -30dB"],
            "vocal band present" => [expected.empty? || vocal.size >= 3, "#{vocal.size} windows with strong 300-3400Hz share#{" (instrumental score: not required)" if expected.empty?}"],
            "no long silent tail" => [energy["silence_tail_s"] < 2.5, "#{energy["silence_tail_s"]}s"],
            "lyrics sung" => [(expected - words).empty?, "missing #{(expected - words).inspect}, whisper: #{transcript[:text].inspect}"]
          )
        }
      end

      protected

      def endpoint
        return "local:#{source_file}" if source_file
        project.prompt?("03_score") ? Fal::Models::ElevenMusic25.endpoint : super
      end

      private

      def source_file = project.generation[:music_from]

      def score
        file = project.prompt_path("03_score")
        model = Fal::Models::ElevenMusic25.new(client: client)
        if file.end_with?(".json")
          plan = JSON.parse(project.prompt("03_score"))
          total = plan.fetch("chunks").sum { |c| c.fetch("duration_ms") }
          raise ArgumentError, "03_score.json chunks total #{total}ms, longer than the #{project.duration}s scene" if total > project.duration * 1000 + 50
          model.compose(composition_plan: plan, seed: seed)
        else
          model.compose(prompt: project.prompt("03_score"), duration: project.duration)
        end
      end

      # A stand-in fal result pointing at the local file, so run!/materialize work unchanged.
      def extract(file)
        Result.new(request_id: nil, input: { file: file, offset: project.generation[:music_offset] }.compact,
                   output: { "audio" => { "path" => File.expand_path(file, ROOT) } })
      end

      def ext(url) = File.extname(URI(url).path).then { |e| e.empty? ? ".mp3" : e }

      # Whisper transcript of the fitted master, with segment timestamps.
      def transcribe
        return { text: "", segments: [], skipped: "upload_music: false; local audio review only" } unless project[key]["url"]
        out = Fal::Models::Whisper.new(client: client).transcribe(audio_url: project[key]["url"]).output
        { text: out["text"].to_s.strip, segments: Array(out["chunks"]).map { |c| "#{c["timestamp"]&.join("-")}s #{c["text"].to_s.strip}" } }
      end
    end
  end
end
