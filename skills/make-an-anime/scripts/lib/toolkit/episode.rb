require "fileutils"
require "json"
require "open3"
require "yaml"

module Toolkit
  # Episode-level tools (local, no Fal calls).
  #
  #   scene:new[run,frames]          scaffold a scene: prompts/<run>/ (dialogue, score, keyframes, shots, overlay templates),
  #                                  prompts/<run>-sfx/sfx.yml and config/generations/<run>.rb. Never overwrites.
  #   episode:preview[out,run,...]   join scenes in order into one preview; with a single prefix argument (ep01) every
  #                                  ep01-sNN run is used. Each scene contributes its most finished file:
  #                                  final_sfx.mp4 > final_overlay.mp4 > final.mp4. Missing scenes are reported, not skipped silently.
  class Episode
    FINALS = %w[final_sfx.mp4 final_overlay.mp4 final.mp4].freeze

    def initialize(root: Pipeline::ROOT, ffmpeg: Media::FFmpeg.new)
      @root = root
      @ffmpeg = ffmpeg
    end

    # config/episodes/<prefix>.yml is the playing order when it exists; otherwise scenes play in number order.
    def runs_for(prefix)
      order = File.join(@root, "config", "episodes", "#{prefix}.yml")
      return YAML.safe_load_file(order) if File.file?(order)

      Dir[File.join(@root, "prompts", "#{prefix}-s[0-9]*")].map { File.basename(_1) }.grep(/\A#{Regexp.escape(prefix)}-s\d+\z/).sort
    end

    def final_for(run)
      FINALS.map { |f| File.join(@root, "output", run, f) }.find { |f| File.file?(f) }
    end

    # Scenes are mixed one at a time, so their loudness drifts (six scenes once spanned 3.3 LU); each scene's audio is moved
    # to `lufs` (EBU R128 integrated) before joining, never pushing its true peak above PEAK_CEILING. lufs: nil joins as is.
    # A scene with speech is moved so its voices sit at voice_db instead: levelling a whole scene pulled the loud ones down,
    # and a loud fight scene took its narrator line 7.8 dB under the other lines. The bed follows, within VOICE_GAIN.
    PEAK_CEILING = -1.0
    VOICE_GAIN = (-10.0..6.0)

    def level(picked, dir, lufs:, voice_db: nil, seams: false)
      last = picked.size - 1
      picked.each_with_index.map do |(run, file), i|
        next { path: file } unless lufs
        m = @ffmpeg.loudness(file)
        next { path: file, lufs: m[:lufs], gain_db: 0.0 } unless m[:lufs].finite? && m[:lufs] > -60 # a silent card
        fades = seams ? seam_fades(run, file, first: i.zero?, last: i == last) : { fade_in: 0, fade_out: 0 }
        speech = voice_db && speech_level(run, file)
        wanted = speech ? (voice_db - speech).clamp(VOICE_GAIN) : lufs - m[:lufs]
        db = [wanted, PEAK_CEILING - m[:true_peak]].min.round(2)
        plain = db.abs < 0.1 && fades.values.all?(&:zero?)
        { path: plain ? file : @ffmpeg.gain(file, File.join(dir, "#{run}.mp4"), db: db, **fades), lufs: m[:lufs], speech_db: speech, gain_db: db, **fades }
      end
    end

    # The median level of a scene's narrator lines, or of all its lines when it has no narrator. nil when nobody speaks.
    def speech_level(run, file)
      path = File.join(@root, "output", run, "03_dialogue_lines.json")
      return unless File.exist?(path)
      lines = JSON.parse(File.read(path))
      lines = lines["lines"] if lines.is_a?(Hash)
      lines = Array(lines).select { (_1["speech_at"] || _1["at"]) && _1["end"] && !_1["inner"] && _1["subtitle"] != " " }
      lines = lines.select { _1["vo"] } if lines.any? { _1["vo"] }
      levels = lines.filter_map { @ffmpeg.mean_volume(file, _1["speech_at"] || _1["at"], _1["end"]) }.sort
      levels[levels.size / 2] if levels.any?
    end

    # Every scene's track clearly ends and the next clearly starts. The fade-out takes the air after the last word and the
    # fade-in the air before the first, each kept off the voices; a scene that opens on a hit keeps its hit.
    SEAM = { out: (0.25..1.4), in: (0.15..0.7), hit: 0.02, clear: 0.12 }.freeze

    def seam_fades(run, file, first:, last:)
      seconds = @ffmpeg.duration(file)
      path = File.join(@root, "output", run, "03_dialogue_lines.json")
      lines = File.exist?(path) ? Array(JSON.parse(File.read(path))) : []
      end_at = lines.map { _1["end"].to_f }.max || 0.0
      start_at = lines.map { (_1["speech_at"] || _1["at"]).to_f }.min || seconds
      head = @ffmpeg.mean_volume(file, 0, 0.2).to_f
      body = @ffmpeg.mean_volume(file, 0.2, 1.2).to_f
      opens_on_a_hit = head > body - 1.0 && head > -30
      fade_in = opens_on_a_hit ? SEAM[:hit] : [(start_at - SEAM[:clear]).clamp(SEAM[:in]), [start_at - 0.02, SEAM[:hit]].max].min
      { fade_in: first ? 0 : fade_in.round(3), fade_out: last ? 0 : (seconds - end_at - SEAM[:clear]).clamp(SEAM[:out]).round(3) }
    end

    def preview(out, names, lufs: -23.0, voice_db: nil, seams: false)
      names = runs_for(names.first) if names.size == 1 && !names.first.match?(/-s\d+\z/)
      raise ArgumentError, "no scenes given" if names.empty?
      picked = names.to_h { |run| [run, final_for(run)] }
      missing = picked.select { |_, f| f.nil? }.keys
      raise ArgumentError, "no final video yet for: #{missing.join(", ")}" if missing.any?
      out = File.expand_path(out, @root)
      FileUtils.mkdir_p(File.dirname(out))
      leveled = level(picked, File.join(File.dirname(out), "#{File.basename(out, ".*")}_leveled"), lufs: lufs, voice_db: voice_db, seams: seams)
      @ffmpeg.concat_videos(leveled.map { _1[:path] }, out)
      scenes = picked.each_with_index.map do |(run, file), i|
        { run: run, file: file.delete_prefix("#{@root}/"), seconds: @ffmpeg.duration(file).round(2), **leveled[i].except(:path) }
      end
      { path: out, seconds: @ffmpeg.duration(out).round(2), lufs_target: lufs, scenes: scenes }
    end

    def seam_report(film, episode)
      rows = runs_for(episode).map { |run| [run, @ffmpeg.duration(final_for(run))] }
      list = File.join(@root, "tmp", "seams_#{episode}.json")
      FileUtils.mkdir_p(File.dirname(list))
      File.write(list, JSON.generate(rows))
      out, = Open3.capture2(Media::Python.new.executable, File.join(@root, "tools", "python", "audio_seams.py"), File.expand_path(film, @root), list)
      JSON.parse(out)
    end

    # A new soundtrack on a rendered scene: final_overlay.mp4's picture is copied, not rendered again.
    def reaudio(run)
      project = Pipeline::Project.new(run)
      video = project.path("final_overlay.mp4")
      temp = project.path("final_overlay.reaudio.mp4")
      @ffmpeg.mux(video, project.soundtrack, temp, shortest: false)
      FileUtils.mv(temp, video)
      { run: run, path: video, seconds: @ffmpeg.duration(video).round(3) }
    end

    # prompts/<name>/beats.yml -> cues.yml: cues written in scene frames (f: end is the cut into the next scene) become film
    # frames, read from the scene files the film is joined from, so a scene that grows can't leave a cue on the wrong beat.
    def vfx_cues(name)
      dir = File.join(@root, "prompts", name)
      spec = YAML.safe_load_file(File.join(dir, "beats.yml"))
      at = 0
      scenes = runs_for(spec.fetch("episode")).to_h do |run|
        frames = @ffmpeg.summary(final_for(run)).dig(:video, :frames)
        [run, { start: at, frames: frames }].tap { at += frames }
      end
      cues = spec.fetch("beats").map do |beat|
        scene = scenes.fetch(beat.fetch("run")) { raise ArgumentError, "#{beat["run"]} is not in #{spec["episode"]}" }
        local = beat.fetch("f") == "end" ? scene[:frames] : beat["f"]
        raise ArgumentError, "#{beat} is past the scene's #{scene[:frames]} frames" unless local.is_a?(Integer) && local <= scene[:frames]
        beat.except("run").merge("f" => scene[:start] + local)
      end
      File.write(File.join(dir, "cues.yml"), YAML.dump("source" => spec.fetch("source"), "out" => spec.fetch("out"), "cues" => cues))
      { name: name, cues: cues.size, film_frames: at }
    end

    # The score with a ring-out: output/<run>/03_score_tail.wav, to set as the run's music_from when its last shot is held longer.
    def score_tail(run, source, tail)
      out = File.join(@root, "output", run, "03_score_tail.wav")
      @ffmpeg.ring_out(File.expand_path(source, @root), out, tail: Float(tail))
      { run: run, path: out, seconds: @ffmpeg.duration(out).round(3) }
    end

    def scaffold(run, frames)
      frames = Integer(frames)
      raise ArgumentError, "run must look like ep01-s02" unless run.match?(/\A[a-z0-9]+-s\d+\z/)
      prompts = File.join(@root, "prompts", run)
      config = File.join(@root, "config", "generations", "#{run}.rb")
      sfx = File.join(@root, "prompts", "#{run}-sfx", "sfx.yml")
      existing = [prompts, config, sfx].select { File.exist?(_1) }
      raise ArgumentError, "already exists: #{existing.join(", ")}" if existing.any?
      FileUtils.mkdir_p([prompts, File.dirname(config), File.dirname(sfx)])
      SceneTemplate.new(run, frames).files.each { |name, body| File.write(File.join(prompts, name), body) }
      File.write(config, SceneTemplate.new(run, frames).generation)
      File.write(sfx, SceneTemplate.new(run, frames).sfx)
      { run: run, frames: frames, seconds: frames / 24.0, prompts: prompts, config: config, sfx: sfx,
        next: "write the prompts, then gen:dialogue -> dialogue:timeline -> gen:music -> gen:mix -> gen:keyframes -> gen:shots -> review:camera -> gen:overlay -> sfx:gen/sfx:mix" }
    end
  end

  # The starting files of a new anime scene; every value is a placeholder to replace.
  class SceneTemplate
    def initialize(run, frames)
      @run = run
      @frames = frames
    end

    def seconds = @frames / 24.0

    def generation
      <<~RUBY
        # #{@run}: #{seconds} s = #{@frames} frames. Evaluated inside Pipeline (see the skill's references/tasks.md).
        {
          "#{@run}" => {
            steps: [Steps::Dialogue, Steps::Music, Steps::Mix, Steps::Keyframes, Steps::Shots, Steps::Overlay],
            **scene(#{@frames}), music_fade: 0, mix: { music_db: -6, dialogue_db: 0, duck: true, music_end: #{seconds} }
          }
        }
      RUBY
    end

    def files
      {
        "03_dialogue.yml" => <<~YAML,
          # Lines in scene seconds. character: a config/cast.yml id; vo: true for narration (no mouth track).
          # A character never talks over themself; run dialogue:timeline after generating.
          - name: line-1
            character: CAST_ID
            at: 1.0
            text: "[tag] Line."
        YAML
        "03_score.json" => <<~JSON,
          {"chunks": [{"text": "[Instrumental]", "duration_ms": #{(seconds * 1000).round}, "positive_styles": ["STYLE"], "negative_styles": ["vocals", "lyrics"]}]}
        JSON
        "02_keyframes.yml" => <<~YAML,
          # One still per H3 shot (or per base it is edited from). refs: accepted sheet runs, in the order the prompt names them.
          key-1:
            base: false
            refs: [char-CAST-v1, loc-PLACE-v1]
            prompt: >-
              {{STYLE}} The person from image 1 … in the place of image 2 … Shot: … 16:9. No text, no other people.
        YAML
        "04_shots.yml" => <<~YAML,
          # Frames must sum to #{@frames}. image: keyframe | run:<sheet run>; color: "#rrggbb" insert; still: hold.
          # audio: <cast id> on the shot where that character speaks on screen. camera: one named move, stated end framing.
          - name: shot-1
            image: key-1
            frames: #{@frames}
            prompt: "{{STYLE}} What moves and how."
            camera: { move: "slow push-in (dolly in), no rotation", from: "medium shot", to: "medium close-up", timing: "whole shot, ease-in-out" }
        YAML
        "05_overlay.js" => <<~JS,
          // #{@run} overlay: subtitles and any readable screen (tools/p5/lib/screens.js). Generated images contain no text.
          Anim.sketch({
            async load() {
              this.f = await Anim.fonts({ sub: "sub.ttf", subItalic: "sub-italic.ttf" });
              this.lines = Anim.data("dialogue");
            },
            draw(t) {
              Anim.subtitles(t, this.lines, { font: this.f.sub, italic: this.f.subItalic });
            },
          });
        JS
      }
    end

    def sfx
      <<~YAML
        # #{@run} sound effects over the finished scene (ElevenLabs Sound Effects v3, paid; tones are local). Times in scene seconds.
        source: output/#{@run}/final_overlay.mp4
        out: output/#{@run}/final_sfx.mp4
        rel_db: -8
        peak_db: -6
        max_gain_db: 18
        sounds:
          ambience: {prompt: "PLACE ambience, no music, no voices", duration: 10}
        cues:
          - {at: 0.0, sound: ambience, rel_db: -12, len: #{seconds}, fade: 0.8}
      YAML
    end
  end
end
