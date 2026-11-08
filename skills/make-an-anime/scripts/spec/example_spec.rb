require_relative "spec_helper"

RSpec.describe "Bundled examples" do
  EXAMPLES = %w[01-sample-seven 02-final-inspection 03-riverbank-bout 04-too-salty].freeze
  STARTER = "01-sample-seven"
  FONTS = JSON.parse(File.read(File.join(SKILL, "examples", STARTER, "config", "fonts.json")))

  def init_example(dir, name = STARTER)
    out, err, status = cli("init", "--project", dir, "--example", name)
    raise "#{out}\n#{err}" unless status.success?
    JSON.parse(out)
  end

  def scene_run(project) = Dir.children(File.join(project, "prompts")).find { _1.end_with?("-s01") }

  it "bundles exactly the four examples, each with a story, a plan and a style, and says they only showcase workflows", :core do
    expect(Dir.children(File.join(SKILL, "examples")).select { File.directory?(File.join(SKILL, "examples", _1)) }.sort).to eq(EXAMPLES)
    expect(File.read(File.join(SKILL, "examples", "README.md"))).to include("must not influence")
    EXAMPLES.each do |name|
      %w[story.md docs/PLAN.md config/style.md config/cast.yml config/generations.rb].each do |path|
        expect(File.file?(File.join(SKILL, "examples", name, path))).to be(true), "#{name}/#{path}"
      end
    end
  end

  EXAMPLES.each do |name|
    it "#{name}: initialises, its shots fill the scene and its prompts pass the believable rules", :core do
      Dir.mktmpdir do |tmp|
        project = File.join(tmp, "p")
        expect(init_example(project, name)).to include("example" => name)
        run = scene_run(project)
        shots = YAML.safe_load_file(File.join(project, "prompts", run, "04_shots.yml"))
        frames = File.read(File.join(project, "config", "generations.rb"))[/"#{run}".*?scene\((\d+)\)/m, 1].to_i
        expect(shots.sum { _1["frames"] }).to eq(frames)
        cast = YAML.safe_load_file(File.join(project, "config", "cast.yml"))
        lines = YAML.safe_load_file(File.join(project, "prompts", run, "03_dialogue.yml"))
        expect(lines.map { _1["character"] }.uniq - cast.keys).to be_empty
        out, err, status = cli("--project", project, "review:believable", env: { "RUN" => run })
        expect(status.success?).to be(true), err
        expect(JSON.parse(out)).to include("ok" => true, "issues" => [])
      end
    end
  end

  it "refuses an unknown example and a path", :core do
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

  it "generates the starter scene from its real prompts with synthetic media", :media do
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
      expect(summary["calls"].keys.grep(/image-to-video/).sum { summary["calls"][_1] }).to eq(5) # the title is a free colour frame

      final = File.join(project, "output", "lab-s01", "final_overlay.mp4")
      expect(ff.summary(final)[:duration]).to be_within(0.06).of(14.0)
      shots = JSON.parse(File.read(File.join(project, "output", "lab-s01", "05_overlay", "shots.json")))
      expect(shots.map { _1["name"] }).to eq(%w[lab mei flask dash ono title])
    end
  end
end
