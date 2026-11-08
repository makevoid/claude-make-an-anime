module Pipeline
  # Provider selection and input translation shared by shots, clips and video.
  # Selecting Seedance is explicit; existing projects keep their H3 behavior.
  class VideoGeneration
    attr_reader :spec

    def initialize(project:, spec: {}, client: nil)
      @spec = project.generation.fetch(:video, {}).transform_keys(&:to_s).merge(spec)
      @client = client
      @provider = @spec.fetch("model") { ENV.fetch("VIDEO_MODEL", "minimax") }
      raise ArgumentError, "video model must be minimax, h3 or seedance" unless %w[minimax h3 seedance].include?(@provider)
      raise ArgumentError, "Seedance options require model: seedance" if !seedance? && (seedance_options? || @spec["draft_id"])
    end

    def seedance? = @provider == "seedance"
    def completion? = seedance? && !!spec["draft_id"]
    def reference? = seedance? && (spec["mode"] == "reference" || spec["audio"] || %w[image_urls video_urls audio_urls].any? { |k| spec.key?(k) })
    def seconds(value)
      return value unless seedance?
      raise ArgumentError, "Seedance timeline shots need numeric seconds, not auto" if value == "auto"
      Fal::Models::SeedanceImageToVideo.duration(value).to_i
    end

    def model
      return Fal::Models::H3MaxImageToVideo unless seedance?
      return Fal::Models::SeedanceDraftComplete if completion?
      reference? ? Fal::Models::SeedanceReferenceToVideo : Fal::Models::SeedanceImageToVideo
    end

    def generate(prompt: nil, image_url: nil, end_image_url: nil, audio_url: nil, duration: nil, seed: nil)
      adapter = model.new(client: @client || Fal::Client.new)
      return adapter.complete(draft_id: spec.fetch("draft_id"), **spec.slice("codec").transform_keys(&:to_sym)) if completion?
      resolution = spec.fetch("resolution") { ENV.fetch("VIDEO_RES", model::DEFAULT_RES) }
      unless seedance?
        return adapter.animate(prompt: prompt, image_url: image_url, end_image_url: end_image_url,
          target_audio_url: audio_url, duration: duration, seed: seed, resolution: resolution)
      end
      raise ArgumentError, "Seedance mode must be image or reference" if spec["mode"] && !%w[image reference].include?(spec["mode"])
      raise ArgumentError, "Seedance image mode does not support reference audio/media; use mode: reference" if spec["mode"] == "image" && reference?
      options = spec.slice("draft", "generate_audio", "aspect_ratio", "codec", "bitrate_mode", "task", "end_user_id").transform_keys(&:to_sym)
      options.merge!(resolution: resolution, duration: duration, prompt: prompt)
      if reference?
        raise ArgumentError, "Seedance reference mode has no pinned end frame; use image mode without audio" if end_image_url
        images = spec.fetch("image_urls") { Array(image_url) }
        audios = Array(spec["audio_urls"]) + Array(audio_url)
        if audio_url
          options[:prompt] = "#{prompt}\n\nUse @Audio#{audios.size} for the performance timing and speech."
          options[:generate_audio] = spec.fetch("generate_audio", true)
        end
        adapter.animate(**options, image_urls: images, video_urls: spec.fetch("video_urls", []), audio_urls: audios, seed: seed)
      else
        raise ArgumentError, "Seedance image-to-video has no seed input; use reference mode for a seed" if seed
        adapter.animate(**options, image_url: image_url, end_image_url: end_image_url)
      end
    end

    def metadata(result)
      { endpoint: model.endpoint, request_id: result.request_id, input: result.input,
        draft_id: result.output["draft_id"], seed: result.output["seed"] }.compact
    end

    private

    def seedance_options?
      %w[mode image_urls video_urls audio_urls draft task generate_audio].any? { |k| spec.key?(k) }
    end
  end
end
