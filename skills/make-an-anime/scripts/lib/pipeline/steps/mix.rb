module Pipeline
  module Steps
    # Step 3c — the scene soundtrack (local, no Fal call): the score (Music step) ducked under the dialogue (Dialogue step),
    # limited, at the scene's exact length -> 03_mix.wav. Shots, Overlay and the final assembly use it via Project#soundtrack.
    # Generation option `mix: { music_db: -4, dialogue_db: 0, duck: true, music_end: 19.5 }`; music_end hard-cuts the score
    # (a smash cut) with a 30 ms fade, or over music_out seconds; ambience and spot effects are added later by sfx:mix.
    # voice_lift_db raises the voice over the bed and writes 03_mix_ref.wav without it (see Media::Sfx#voice_args).
    # A mix older than its score or dialogue file is stale and is rebuilt without FORCE (a music retake used to leave the
    # old mix in 03_mix.wav and final.mp4).
    class Mix < Step
      def done? = super && !stale?

      def stale?
        built = File.mtime(project[key]["path"])
        newer = [project[:music]&.dig("path"), project[:dialogue]&.dig("path")].compact.select { |p| File.exist?(p) && File.mtime(p) > built }
        warn "[#{key}] stale: #{newer.join(", ")} newer than the mix -> rebuilding" if newer.any?
        newer.any?
      end

      def submit
        Result.new(request_id: nil, input: settings, output: {})
      end

      def materialize(result)
        music = project.fetch!(:music, :path)
        dialogue = project[:dialogue]&.dig("path")
        opts = settings.except("voice_lift_db").transform_keys(&:to_sym)
        lift = settings["voice_lift_db"].to_f
        # The mix without the lift stays beside it: sfx:mix reads cue levels from it, so a louder voice keeps the effects where they were.
        ffmpeg.duck_mix(music, dialogue, project.path("03_mix_ref.wav"), seconds: project.duration, **opts) if lift.positive?
        out = ffmpeg.duck_mix(music, dialogue, project.path("03_mix.wav"), seconds: project.duration, **opts, dialogue_db: opts.fetch(:dialogue_db, 0) + lift)
        { request_id: nil, endpoint: "local:mix", input: result.input.merge("music" => music, "dialogue" => dialogue), path: out }
      end

      def review
        mix = project[key]["path"]
        summary = ffmpeg.summary(mix)
        energy = python.audio_energy(ffmpeg.to_wav(mix, project.review_path(key, "mix.wav")))
        {
          summary: summary, waveform: ffmpeg.waveform(mix, project.review_path(key, "waveform.png")),
          **verdict(
            "scene length" => [(summary[:duration] - project.duration).abs < 0.05, "#{summary[:duration]}s / #{project.duration}s"],
            "not silent" => [energy["windows"].count { |w| w["rms_db"] > -40 } >= energy["windows"].size * 0.5, "#{energy["windows"].count { |w| w["rms_db"] > -40 }}/#{energy["windows"].size} windows > -40dB"]
          )
        }
      end

      protected

      def endpoint = "local:mix"

      private

      def settings = { "music_db" => -4, "dialogue_db" => 0, "duck" => true }.merge(project.generation.fetch(:mix, {}).transform_keys(&:to_s))
    end
  end
end
