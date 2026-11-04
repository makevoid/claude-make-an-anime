require "json"
require "yaml"
require "fileutils"

module Toolkit
  # Anime review tools (all local, no Fal calls):
  #
  #   review:likeness[run,...]  one board per character sheet beside the reference photos it was made from; several runs
  #                             (e.g. v2,v3) are stacked so alternatives compare against the same photos.
  #   review:camera             per H3 shot of RUN: a frame strip, the measured camera move (zoom / pan / tilt between
  #                             the first and last frame) next to the directed `camera:` move, and a verdict hint.
  #   dialogue:timeline         RUN's shots and lines on one timeline with the checks that matter before animating:
  #                             every `audio:` shot contains its speaker's whole on-screen line, no on-screen line
  #                             crosses a cut, the shortest frame count each talking shot needs.
  class AnimeReview
    FPS = 24
    # A camera estimate below this match score is unreliable: strong parallax, a big character move or a morph.
    TRUST = 0.65

    def initialize(project = Pipeline::Project.new)
      @project = project
    end

    attr_reader :project

    def likeness(runs)
      runs = [project.name] if runs.empty?
      sheets = runs.map { |run| Pipeline::Project.new(run) }
      photos = sheets.flat_map { |p| reference_photos(p) }.uniq.first(8)
      raise ArgumentError, "no reference photos (generation photos:) for #{runs.join(", ")}" if photos.empty?
      dir = sheets.first.path("review")
      FileUtils.mkdir_p(dir)
      row = File.join(dir, "likeness_photos.jpg")
      magick.board(photos.each_with_index.map { |p, i| [p, "#{i + 1}. #{File.basename(p, ".*")[-16..] || File.basename(p, ".*")}"] }, row, width: 300)
      boards = sheets.map do |p|
        out = File.join(dir, "likeness_#{p.name}.jpg")
        magick.preview(p.fetch!(:ref_base, :path), out, max: 1800)
        out
      end
      out = File.join(dir, "likeness_#{runs.join("_vs_")}.jpg")
      magick.stack([row, *boards], out, width: 1800)
      { board: out, photos: photos, sheets: runs,
        check: "Front-view close-up vs the front photos first: face shape and width, eye size/lids, brows, nose, mouth, skin, build. Then hair, beard, glasses." }
    end

    def camera
      shots = Pipeline::Steps::Shots.new(project: project).specs
      dir = project.path("review", "camera")
      FileUtils.mkdir_p(dir)
      shots.filter_map do |name, spec|
        next if spec["still"] || spec["color"] || spec["from_run"]
        video = project.path("04_shot_#{name}.mp4")
        next unless File.file?(video)
        n = ffmpeg.summary(video).dig(:video, :frames) || (ffmpeg.duration(video) * FPS).round
        first = ffmpeg.frame_index(video, 0, File.join(dir, "#{name}_first.png"))
        last = ffmpeg.frame_index(video, [n - 1, 0].max, File.join(dir, "#{name}_last.png"))
        # ~4 fps (12 frames per 3 s row): dense enough to see an H3-inserted cut or a story action done early, which
        # neither the camera estimate nor frame-difference scores separate from normal character motion.
        strip = ffmpeg.contact_sheet(video, File.join(dir, "#{name}_strip.jpg"), cols: 12, rows: (n / 72.0).ceil.clamp(1, 4), width: 320)
        measured = python.camera_motion(first, last)
        directed = spec["camera"].is_a?(Hash) ? spec["camera"]["move"] : spec["camera"]
        { shot: name, directed: directed, measured: measured["camera"], zoom: measured["zoom"],
          shift: [measured["shift_x"], measured["shift_y"]], score: measured["score"],
          hint: hint(directed.to_s, measured), strip: strip, first: first, last: last }
      end
    end

    def timeline
      lines_path = project.path("03_dialogue_lines.json")
      raise ArgumentError, "run gen:dialogue first (#{lines_path})" unless File.file?(lines_path)
      lines = JSON.parse(File.read(lines_path))
      shots = Pipeline::Steps::Shots.new(project: project).specs.map do |name, s|
        { name: name, from: s["start_frame"] / FPS.to_f, to: (s["start_frame"] + s["frames"]) / FPS.to_f,
          frames: s["frames"], audio: s["audio"], kind: s["color"] ? "colour" : s["still"] ? "still" : "h3" }
      end
      issues = []
      rows = shots.map do |s|
        inside = lines.select { |l| l["at"] < s[:to] && l["end"] > s[:from] }
        if s[:audio].is_a?(String) && s[:audio] != "dialogue"
          own = inside.reject { |l| l["vo"] }.select { |l| l["character"] == s[:audio] }
          issues << "#{s[:name]}: audio #{s[:audio]} but none of their on-screen lines play here" if own.empty?
          own.each do |l|
            next if l["at"] >= s[:from] && l["end"] <= s[:to]
            issues << format("%s: %s's line %s (%.2f–%.2f s) crosses the shot (%.2f–%.2f s)", s[:name], s[:audio], l["name"], l["at"], l["end"], s[:from], s[:to])
          end
        end
        inside.reject { |l| l["vo"] }.each do |l|
          next if l["at"] >= s[:from] && l["end"] <= s[:to]
          issues << format("%s: on-screen line %s crosses a cut (%.2f–%.2f s); move the cut or the line", s[:name], l["name"], l["at"], l["end"])
        end
        need = s[:audio] ? ((inside.map { |l| l["end"] }.max || s[:from]) - s[:from] + 0.25) * FPS : nil
        { shot: s[:name], frames: s[:frames], seconds: format("%.2f–%.2f", s[:from], s[:to]), kind: s[:kind], audio: s[:audio],
          lines: inside.map { |l| format("%s%s %.2f–%.2f", l["name"], l["vo"] ? " (VO)" : "", l["at"], l["end"]) },
          min_frames_for_lines: need&.ceil }
      end
      { run: project.name, frames: shots.sum { _1[:frames] }, shots: rows, issues: issues.uniq, ok: issues.empty? }
    end

    private

    def reference_photos(p)
      Array(p.generation[:photos]).map { |f| File.expand_path(f, Pipeline::ROOT) }
                                  .reject { |f| f.include?("/output/") } # sheets passed as style references
                                  .select { |f| File.file?(f) }
    end

    def hint(directed, m)
      return "unreliable estimate (score #{m["score"]}): parallax or character motion — judge the strip by eye" if m["score"] < TRUST
      d = directed.downcase
      want = if d.match?(/push|dolly[- ]?in|zoom[- ]?in|track(ing)?[- ]?in/) then :in
             elsif d.match?(/pull|dolly[- ]?out|zoom[- ]?out|track(ing)?[- ]?out/) then :out
             elsif d.match?(/static|locked|no camera move/) then :static
             end
      got = m["zoom"] > 1.03 ? :in : m["zoom"] < 0.97 ? :out : :static
      moved = m["shift_x"].abs >= 0.02 || m["shift_y"].abs >= 0.02
      return "no comparable directed move" unless want
      return "matches" if want == got && (want != :static || !moved)
      "MISMATCH: directed #{want}, measured #{m["camera"]}"
    end

    def ffmpeg = @ffmpeg ||= Media::FFmpeg.new
    def python = @python ||= Media::Python.new
    def magick = @magick ||= Media::ImageMagick.new
  end
end
