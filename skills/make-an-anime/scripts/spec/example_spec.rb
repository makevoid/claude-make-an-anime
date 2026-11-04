require_relative "spec_helper"

RSpec.describe "Bundled shonen-battle example" do
  EXAMPLE = File.join(SKILL, "examples", "shonen-battle")
  FONTS = JSON.parse(File.read(File.join(EXAMPLE, "config", "fonts.json")))

  def init_example(dir)
    out, err, status = cli("init", "--project", dir, "--example", "shonen-battle")
    raise "#{out}\n#{err}" unless status.success?
    JSON.parse(out)
  end

  it "is an initialised, valid 12 s project with the three directed sections", :core do
    Dir.mktmpdir do |tmp|
      project = File.join(tmp, "p")
      expect(init_example(project)).to include("example" => "shonen-battle")
      expect(File.file?(File.join(project, "config", "cast.yml"))).to be(true)
      expect(File.read(File.join(project, "docs", "BRIEF.md"))).to include("EMBER")

      shots = YAML.safe_load_file(File.join(project, "prompts", "shonen-s01", "04_shots.yml"))
      expect(shots.map { [_1["name"], _1["frames"]] }).to eq([["title", 48], ["composite-plate", 120], ["full-h3", 120]])
      expect(shots[1]["roll"]).to eq([-9, 9])
      expect(shots[2]).to include("image" => "clash")

      clips = YAML.safe_load_file(File.join(project, "prompts", "shonen-s01", "04_clips.yml"))
      expect(clips.map { _1["key"] }).to all(eq("green"))
      expect(clips.map { _1["audio_at"] }).to all(eq(2.0))
      cast = YAML.safe_load_file(File.join(project, "config", "cast.yml"))
      expect(clips.map { _1["audio"] }).to match_array(cast.keys)
    end
  end

  it "refuses an unknown example and a missing story", :core do
    Dir.mktmpdir do |tmp|
      _, err, status = cli("init", "--project", File.join(tmp, "p"), "--example", "nope")
      expect(status.success?).to be(false)
      expect(err).to include("No example nope")
      _, _, status = cli("init", "--project", File.join(tmp, "q"), "--example", "../secrets")
      expect(status.success?).to be(false)
    end
  end

  it "computes an overscan that hides the corners of a rolled frame", :core do
    expect(Media::FFmpeg.roll_overscan(0, 1920, 1080)).to eq(1.0)
    expect(Media::FFmpeg.roll_overscan(-9, 1920, 1080)).to be_within(0.001).of(Math.cos(9 * Math::PI / 180) + (16.0 / 9) * Math.sin(9 * Math::PI / 180))
  end

  it "rolls a plate at the requested angle, with no black corners", :media do
    src = file("plate.mp4")
    ff.run("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "color=#c04020:s=640x360:r=24:d=2", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", src)
    out = ff.concat_shots([{ path: src, frames: 48, roll: [-9, 9] }], file("rolled.mp4"), fps: 24, w: 640, h: 360)
    expect(ff.summary(out)[:duration]).to be_within(0.05).of(2.0)
    [0, 24, 47].each do |n|
      frame = ff.frame_index(out, n, file("f#{n}.png"))
      corners = [[0, 0], [639, 0], [0, 359], [639, 359]].map { |x, y| magick.run("magick", frame, "-format", "%[fx:p{#{x},#{y}}.r]", "info:", quiet: true).to_f }
      expect(corners).to all(be > 0.5)
    end
  end

  it "generates the whole scene from its real prompts with synthetic media", :media do
    missing = FONTS.values.reject { File.file?(_1) }
    skip "system fonts missing: #{missing.join(", ")}" if missing.any?
    Dir.mktmpdir do |tmp|
      project = File.join(tmp, "p")
      init_example(project)
      FileUtils.ln_s(File.join(RT, "node_modules"), File.join(project, "node_modules"))
      env = { "MV_PYTHON" => ENV.fetch("MV_PYTHON", File.join(RT, ".venv", "bin", "python3")) }
      _, err, status = Open3.capture3(env, RbConfig.ruby, "mv.rb", "fonts:copy[config/fonts.json]", chdir: project)
      expect(status.success?).to be(true), err
      out, err, status = Open3.capture3(env, RbConfig.ruby, "spec/support/example_driver.rb", chdir: project)
      expect(status.success?).to be(true), "#{out}\n#{err}"
      summary = JSON.parse(out.lines.last)
      expect(summary["calls"].keys.grep(/image-to-video/).sum { summary["calls"][_1] }).to eq(4) # 2 sprites, plate, full H3

      final = File.join(project, "output", "shonen-s01", "final_overlay.mp4")
      info = ff.summary(final)
      expect(info[:duration]).to be_within(0.06).of(12.0)
      expect(Dir[File.join(project, "output", "shonen-s01", "04_clips", "kaen", "*.png")].size).to eq(120)
      shots = JSON.parse(File.read(File.join(project, "output", "shonen-s01", "05_overlay", "shots.json")))
      expect(shots.find { _1["name"] == "composite-plate" }["roll"]).to eq([-9, 9])
    end
  end
end
