require "yaml"

module Pipeline
  # A step made of several named fal generations (keyframes, shots) listed in a prompts/<run>/ YAML file.
  # run! generates the items that are missing or stale (#stale_item?); FORCE=1 regenerates all of them, or only ONLY=a,b.
  # Replaced items are copied to output/<RUN>/rejected/ and kept in the manifest's history.
  # Subclasses implement #specs ({ name => spec }), #generate(name, spec) -> item hash (with "path")
  # and #finish(items) -> step data (with :path, the step's deliverable).
  class ItemsStep < Step
    def run!(force: ENV["FORCE"] == "1")
      only = ENV["ONLY"]&.split(",")
      unknown = Array(only) - specs.keys
      raise "[#{key}] unknown ONLY=#{unknown.join(",")} (#{specs.keys.join(", ")})" if unknown.any?
      items = (project[key]&.dig("items") || {}).slice(*specs.keys)
      specs.each do |name, spec|
        next if only && !only.include?(name)
        next if items[name] && File.exist?(items[name]["path"]) && !stale_item?(name, spec, items[name]) && !(force && (only.nil? || only.include?(name)))
        archive_item!(name, items[name]) if items[name]
        warn "[#{key}] #{name} generating…"
        started = Time.now
        items[name] = generate(name, spec).transform_keys(&:to_s).merge("elapsed_s" => (Time.now - started).round(1))
        project.record(key, items: items) # keep progress if a later item fails
      end
      if (specs.keys - items.keys).empty?
        project.record(key, finish(items).merge(items: items, review: nil))
      else
        project.record(key, items: items, review: nil)
      end
    end

    # A cached item a subclass knows is out of date with its spec (e.g. a free local shot whose frames changed).
    def stale_item?(_name, _spec, _item) = false

    def adopt!(*) = raise("[#{key}] has several items; regenerate one with ONLY=<name> FORCE=1 rake gen:#{key}")
    def pick!(*) = adopt!

    protected

    # H3 inputs shared by the Shots and Clips steps: a keyframe (Keyframes step, "<run>/<name>" for another run's) or "ref_base" as an image url,
    # and the master song from `from` seconds (`seconds` long, shorter at the end), uploaded for H3.
    # H3 rejects audio under 2s, so a clip near the end of the song gets its tail padded with silence.
    def keyframe_url(name)
      return project.fetch!(:ref_base, :url) if name == "ref_base"
      return Project.new(name.delete_prefix("run:")).fetch!(:ref_base, :url) if name.start_with?("run:") # a location/character sheet run
      project.keyframe(name)["url"]
    end

    def song_url(name, from, seconds)
      audio = ffmpeg.cut_audio(project.fetch!(:music, :path), project.path("04_audio_#{name}.mp3"), from: from, seconds: seconds)
      audio = ffmpeg.fit_audio(audio, project.path("04_audio_#{name}_2s.mp3"), seconds: 2, fade: 0) if ffmpeg.duration(audio) < 2
      client.upload(audio)
    end

    # `seconds` of a Dialogue track from scene time `from`, uploaded as H3 target audio: track is a cast id (that
    # character's on-screen lines only) or "dialogue" (every line). Padded with silence to H3's 2 s minimum.
    def voice_url(name, track, from, seconds)
      data = project.fetch!(:dialogue, :path) && project[:dialogue]
      source = track == "dialogue" ? data["path"] : data.fetch("tracks").fetch(track) { raise "[#{key}] #{name}: no dialogue track #{track.inspect} (#{data["tracks"].keys.join(", ")})" }
      out = project.path("04_voice_#{name}.wav")
      ffmpeg.run("ffmpeg", "-y", "-v", "error", "-ss", from.round(4).to_s, "-i", source, "-t", seconds.to_s, "-ar", "44100", out)
      out = ffmpeg.fit_audio(out, project.path("04_voice_#{name}_2s.wav"), seconds: [seconds, 2].max, fade: 0) if ffmpeg.duration(out) < [seconds, 2].max - 0.02
      client.upload(out)
    end

    # prompts/<run>/<stem>.yml as { "name" => spec }. {{STYLE}} is expanded inside the parsed strings, never in the raw
    # YAML: the style text may contain quotes or colons that would break a quoted or plain scalar.
    def yaml(stem) = expand_strings(YAML.safe_load(File.read(project.prompt_path(stem))))

    def expand_strings(value)
      case value
      when String then project.expand(value)
      when Array then value.map { expand_strings(_1) }
      when Hash then value.transform_values { expand_strings(_1) }
      else value
      end
    end

    private

    def archive_item!(name, item)
      history = Array(project[key]&.dig("history"))
      dest = project.path("rejected", "#{key}_#{name}_#{history.count { |h| h["item"] == name } + 1}#{File.extname(item["path"])}")
      FileUtils.cp(item["path"], dest) if File.exist?(item["path"])
      project.record(key, history: history + [item.merge("item" => name, "archived" => dest)])
      warn "[#{key}] archived #{name} -> #{dest}"
    end
  end
end
