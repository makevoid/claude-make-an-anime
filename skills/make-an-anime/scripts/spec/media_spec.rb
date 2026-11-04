require_relative "spec_helper"
RSpec.describe "Local media end to end", :media do
  it "executes the documented intake and audio-analysis task in a fresh project" do
    song = tone(duration: 3)
    File.write(file("brief.md"), "A robot band, visual puns and dramatic drop")
    destination = file("new project")
    _, err, status = cli("init", "--project", destination, "--song", song, "--prompt-file", file("brief.md"))
    expect(status.exitstatus).to eq(0), err
    out, err, status = cli("--project", destination, "audio:analyze[audio/source.wav,audio]")
    expect(status.exitstatus).to eq(0), err
    expect(JSON.parse(out)["duration"]).to be_within(0.01).of(3)
    expect(File.file?(File.join(destination,"tools/python/beats.py"))).to be(true)
    expect(File.file?(File.join(destination,".skill/SKILL.md"))).to be(true)
    expect(File.directory?(File.join(destination,"node_modules"))).to be(false)
    expect(File.directory?(File.join(destination,"tools/vfx/.build"))).to be(false)
  end
  it "renders typography, timing and graphics helpers without bundled font files" do
    result = Media::Anim.new.render(File.join(RT,"tools/p5/examples/smoke.js"), file("smoke"), width: 1920, height: 1080, fps: 24, frames: 48, only: [0,24,47])
    expect(result["frames"]).to eq(3)
    expect(magick.alpha_coverage(file("smoke/0024.png"))).to be > 0.03
    expect(File.binread(file("smoke/0000.png"))).not_to eq(File.binread(file("smoke/0047.png")))
  end
  it "isolates drawing state per frame, so a full render matches single-frame previews" do
    File.write(file("leak.js"), <<~JS)
      Anim.sketch({
        draw(t, frame) {
          if (frame === 0) { textAlign(RIGHT, TOP); fill(255, 0, 0); }   // a helper that forgets to restore state
          textSize(60); text("LEFT", 0, 90);                             // default LEFT alignment draws on canvas
        },
      });
    JS
    Media::Anim.new.render(file("leak.js"), file("leak"), width: 320, height: 180, fps: 24, frames: 2)
    lit = ->(png) { Media::ImageMagick.new.run("magick", png, "-alpha", "extract", "-format", "%[fx:mean]", "info:", quiet: true).to_f }
    expect(lit.(file("leak/0001.png"))).to be > 0.01
  end

  it "starts a subtitle where the voice starts (speech_at), not at a silent take head or a late word cue" do
    take = file("take.wav")
    ff.run("ffmpeg", "-y", "-v", "error", "-i", tone(file("t.wav"), duration: 1), "-af", "adelay=700|700", take, quiet: true)
    expect(ff.leading_silence(take)).to be_within(0.05).of(0.7)
    expect(ff.leading_silence(tone(file("t2.wav"), duration: 1))).to eq(0.0)
    File.write(file("subs.js"), <<~JS)
      Anim.sketch({ draw(t) { background(0); Anim.subtitles(t, Anim.data("dialogue"), { font: "sans-serif" }); } });
    JS
    File.write(file("dialogue.json"), JSON.generate([{ name: "eat", text: "[tired] Eat, amore.", at: 0.0, speech_at: 0.5, end: 1.0 }]))
    # Misleading word cues (as ElevenLabs gave after a long tag) must not delay the subtitle: speech_at wins.
    File.write(file("words.json"), JSON.generate([{ w: "Eat", s: 0.9, e: 0.95, line: "eat" }, { w: "amore", s: 0.95, e: 1.0, line: "eat" }]))
    Media::Anim.new.render(file("subs.js"), file("subs"), width: 640, height: 360, fps: 24, frames: 24, only: [6, 18],
                           data: { dialogue: file("dialogue.json"), words: file("words.json") })
    lit = ->(f) { magick.run("magick", f, "-colorspace", "gray", "-threshold", "50%", "-format", "%[fx:mean]", "info:", quiet: true).to_f }
    expect(lit.(file("subs/0006.png"))).to eq(0.0)
    expect(lit.(file("subs/0018.png"))).to be > 0.001
    # A `subtitle:` gloss is drawn instead of the spoken text (wider string -> more lit pixels).
    File.write(file("dialogue.json"), JSON.generate([{ name: "eat", text: "[tired] Eat, amore.", subtitle: "Eat, amore. (Eat, my love.)", at: 0.0, speech_at: 0.5, end: 1.0 }]))
    Media::Anim.new.render(file("subs.js"), file("subs2"), width: 640, height: 360, fps: 24, frames: 24, only: [18],
                           data: { dialogue: file("dialogue.json"), words: file("words.json") })
    expect(lit.(file("subs2/0018.png"))).to be > lit.(file("subs/0018.png")) * 1.5
  end
  it "cuts a shot to its first source_frames and retimes them to the shot length" do
    src = file("take.mp4")
    ff.run("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24:duration=2", "-pix_fmt", "yuv420p", src, quiet: true)
    out = ff.concat_shots([{ path: src, frames: 48, retime: true, keep: 24, skip: 0 }], file("kept.mp4"), fps: 24)
    expect(ff.summary(out).dig(:video, :frames)).to eq(48)
    diff = ->(a, b) { Open3.capture3("magick", "compare", "-metric", "RMSE", a, b, "null:")[1][/\(([\d.e-]+)\)/, 1].to_f }
    last = ff.frame_index(out, 47, file("kept_last.png"))
    src23 = ff.frame_index(src, 23, file("src23.png")); src47 = ff.frame_index(src, 47, file("src47.png"))
    expect(diff.(last, src23)).to be < diff.(last, src47)
    # An uneven stretch (72 kept frames -> 96) used to come out one frame short.
    odd = ff.concat_shots([{ path: src, frames: 96, retime: true, keep: 36, skip: 0 }, { path: src, frames: 20, retime: true }], file("odd.mp4"), fps: 24)
    expect(ff.summary(odd).dig(:video, :frames)).to eq(116)
  end
  it "levels a take by its gain_db when placing lines, leaving lines without one untouched" do
    take = tone(file("take.wav"), duration: 1)
    rms = lambda do |path, from|
      _, err, = Open3.capture3("ffmpeg", "-v", "info", "-ss", from.to_s, "-t", "0.8", "-i", path, "-af", "astats=measure_overall=RMS_level:measure_perchannel=0", "-f", "null", "-")
      err[/RMS level dB:\s*(-?[\d.]+)/, 1].to_f
    end
    out = ff.place_audio([{ "at" => 0.0, "path" => take }, { "at" => 2.0, "path" => take, "gain_db" => -6.0 }], file("placed.wav"), seconds: 3.5)
    expect(rms.(out, 2.1) - rms.(out, 0.1)).to be_within(0.3).of(-6.0)
  end
  it "detects audio duration, a real silent tail and vocal-band energy through Python" do
    song = tone(duration: 4)
    Toolkit::Operations.new.analyze_audio(song, file("analysis"))
    energy = JSON.parse(File.read(file("analysis/energy.json")))
    expect(energy["duration"]).to be_within(0.02).of(4)
    expect(energy["silence_tail_s"]).to be >= 0.5
    expect(energy["windows"].first["vocal_ratio"]).to be > 0.9
    beats = JSON.parse(File.read(file("analysis/beats.json")))
    expect(beats.fetch("beats")).not_to be_empty
  end
  it "finds a hard cut at the expected frame through Python" do
    ff.run("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "color=black:s=320x180:r=24:d=1", "-f", "lavfi", "-i", "color=white:s=320x180:r=24:d=1", "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0", "-c:v", "libx264", file("cuts.mp4"))
    data = py.call("cuts.py", file("cuts.mp4"))
    expect(data["cuts"].map { |c| c["f"] }).to include(24)
    expect(data["frames"]).to eq(48)
  end
  it "cuts out green, preserves the character and renders it at the intended p5 position" do
    meta = py.cutout(character, file("sprite"), "green")
    rgba = pixels(file("sprite/0000.png"))
    expect(rgba[0][3]).to eq(0)
    expect(rgba[90 * 320 + 160][3]).to be > 250
    meta["dir"] = file("sprite").delete_prefix("#{RT}/")
    json(file("clips.json"), hero: meta)
    File.write(file("scene.js"), <<~JS)
      Anim.sketch({
        async load() { this.hero = await Anim.clip('hero'); },
        draw(t, frame) { background('#102030'); this.hero.draw(this.hero.frame(0), 240, 90, 180); noStroke(); fill('#ffffff'); rect(8 + frame * 2, 8, 8, 8); }
      });
    JS
    renderer = Media::Anim.new
    renderer.render(file("scene.js"), file("frames"), width: 320, height: 180, fps: 24, frames: 24, data: {clips: file("clips.json")})
    png = pixels(file("frames/0000.png"))
    red = png.each_index.select { |i| r,g,b,_ = png[i]; r > 170 && g < 90 && b < 110 }
    xs = red.map { |i| i % 320 }; ys = red.map { |i| i / 320 }
    expect(xs.min).to be_within(3).of(208)
    expect(xs.max).to be_within(3).of(272)
    expect(ys.min).to be_within(3).of(36)
    expect(ys.max).to be_within(3).of(144)
    expect(Digest::SHA256.file(file("frames/0000.png")).hexdigest).not_to eq(Digest::SHA256.file(file("frames/0023.png")).hexdigest)
    renderer.render(file("scene.js"), file("repeat"), width: 320, height: 180, fps: 24, frames: 24, only: [0], data: {clips: file("clips.json")})
    expect(File.binread(file("repeat/0000.png"))).to eq(File.binread(file("frames/0000.png")))
    base = video(seconds: 1)
    ff.overlay_frames(base, file("frames"), file("scene.mp4"), fps: 24)
    info = ff.summary(file("scene.mp4"))
    expect(info.dig(:video, :frames)).to eq(24)
    expect(info.dig(:audio, :codec)).to eq("aac")
  end
  it "assembles contiguous sections without losing frames or the original soundtrack timing" do
    song = tone(duration: 2)
    runs = %w[e2e-join-a e2e-join-b]
    generations = runs.each_with_index.to_h { |name, i| [name, {steps: [], **Pipeline.section(i * 24, 24), music_from: song}] }
    stub_const("Pipeline::GENERATIONS", generations)
    runs.each do |run|
      project = Pipeline::Project.new(run)
      video(project.path("final_overlay.mp4"), audio: song, seconds: 1)
    end
    Toolkit::Operations.new.preview(file("joined.mp4"), runs)
    info = ff.summary(file("joined.mp4"))
    expect(info.dig(:video, :frames)).to eq(48)
    expect(info[:duration]).to be_within(0.06).of(2)
    original = ff.run("ffmpeg", "-v", "error", "-i", song, "-ac", "1", "-f", "s16le", "-", quiet: true).unpack("s<*")
    joined = ff.run("ffmpeg", "-v", "error", "-i", file("joined.mp4"), "-ac", "1", "-ar", "44100", "-f", "s16le", "-", quiet: true).unpack("s<*")
    size = [original.size, joined.size].min
    dot = original.take(size).zip(joined).sum { |x,y| x * y }
    norm = Math.sqrt(original.take(size).sum { |x| x*x } * joined.take(size).sum { |x| x*x })
    expect(dot / norm).to be > 0.98
  end
  it "mixes a timed sound effect, limits peaks and keeps the video frames" do
    source = video(seconds: 2)
    name = "e2e-sfx-#{Process.pid}"
    config_dir = File.join(RT, "prompts", name); FileUtils.mkdir_p(config_dir)
    File.write(File.join(config_dir, "sfx.yml"), YAML.dump({"source" => source, "out" => file("mixed.mp4"), "sounds" => {"beep" => {"tone" => 1200, "duration" => 0.3}}, "cues" => [{"sound" => "beep", "at" => 0.75, "rel_db" => -4}]}))
    service = Media::Sfx.new(name)
    service.generate(client: double("no Fal calls for tones"))
    out, report = service.mix
    expect(ff.summary(out).dig(:video, :frames)).to eq(48)
    expect(report).not_to be_empty
    dry = ff.run("ffmpeg", "-v", "error", "-i", source, "-ac", "1", "-ar", "48000", "-f", "s16le", "-", quiet: true).unpack("s<*")
    wet = ff.run("ffmpeg", "-v", "error", "-i", out, "-ac", "1", "-ar", "48000", "-f", "s16le", "-", quiet: true).unpack("s<*")
    expect(wet.map(&:abs).max).to be < 32767
    diff = ->(from, len) { wet.slice(from,len).zip(dry.slice(from,len)).sum { |a,b| (a-b).abs }.fdiv(len) }
    expect(diff.call(38_000, 5_000)).to be > diff.call(5_000, 5_000) * 3
  end
end
