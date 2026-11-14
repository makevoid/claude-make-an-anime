require_relative "spec_helper"

# The VFX pass without Swift: tools/python/mvfx.py through the same Media::Vfx service (MV_VFX=python).
RSpec.describe "Python VFX port", :media do
  CUES = [
    { "fx" => "punch", "f" => 4, "dur" => 4, "amt" => 0.1, "radius" => 6 },
    { "fx" => "zoom", "f" => 10, "dur" => 4, "amt" => 0.12 },
    { "fx" => "shake", "f" => 16, "dur" => 4, "amt" => 10 },
    { "fx" => "whip", "f" => 22, "dur" => 3, "pre" => 1, "amt" => 0.2 },
    { "fx" => "mblur", "f" => 27, "dur" => 3, "amt" => 20 },
    { "fx" => "edgeblur", "f" => 32, "dur" => 4, "amt" => 8, "fade" => 1 },
    { "fx" => "glow", "f" => 38, "dur" => 3, "radius" => 8 },
    { "fx" => "flash", "f" => 43, "dur" => 3 },
    { "fx" => "dark", "f" => 48, "dur" => 6, "hold" => 3, "amt" => 0.9 },
    { "fx" => "rgb", "f" => 56, "dur" => 3, "amt" => 0.03 },
    { "fx" => "glitch", "f" => 61, "dur" => 4, "fade" => 1, "seed" => 3 },
    { "fx" => "tv", "f" => 67, "dur" => 5, "fade" => 1 },
    { "fx" => "grain", "f" => 74, "dur" => 5, "fade" => 1, "amt" => 0.5 }
  ].freeze
  HIT = { "punch" => 4, "zoom" => 12, "shake" => 16, "whip" => 22, "mblur" => 27, "edgeblur" => 33, "glow" => 38, "flash" => 43,
          "dark" => 49, "rgb" => 56, "glitch" => 62, "tv" => 68, "grain" => 75 }.freeze
  CLEAN = [0, 2, 20, 90].freeze

  def plate(path = file("plate.png"))
    magick.run("magick", "-size", "320x180", "pattern:checkerboard", "-fill", "#e02040", "-draw", "rectangle 128,36 192,144",
               "-fill", "#2060e0", "-draw", "circle 60,60 60,90", path)
    path
  end

  def diff(a, b)
    magick.run("magick", a, b, "-compose", "difference", "-composite", "-colorspace", "gray", "-format", "%[fx:mean]", "info:",
               quiet: true).to_f
  end

  def stream_hash(path)
    ff.run("ffmpeg", "-v", "error", "-i", path, "-map", "0:v:0", "-c", "copy", "-f", "hash", "-hash", "sha256", "-", quiet: true).strip
  end

  it "renders every Core Image cue, leaves untouched frames alone, cuts clips and stills, and repeats exactly" do
    unless Media::Vfx.python_ready?
      # macOS renders VFX with Swift, so setup leaves OpenCV out there; everywhere else it is the VFX backend.
      raise "numpy and opencv-python-headless are required for the Python VFX port; run setup" unless RUBY_PLATFORM.include?("darwin")
      skip "opencv-python-headless not installed (macOS uses Swift); pip install it to test the Python port"
    end
    ENV["MV_VFX"] = "python"
    expect(Media::Vfx.backend).to eq("python")
    source = video(file("source.mp4"), image: plate, audio: tone(file("song4.wav"), duration: 4), seconds: 4)
    name = "py-vfx-#{Process.pid}"
    dir = File.join(RT, "prompts", name)
    FileUtils.mkdir_p(dir)
    config = { "source" => source, "out" => file("effect.mp4"), "cues" => CUES.map(&:dup) }
    File.write(File.join(dir, "cues.yml"), YAML.dump(config))
    service = Media::Vfx.new(name)
    expect(service.render).to eq(file("effect.mp4"))

    info = ff.summary(file("effect.mp4"))
    expect(info.dig(:video, :frames)).to eq(96)
    expect(info.dig(:audio, :codec)).to eq("aac")
    (CLEAN + HIT.values).each do |f|
      ff.frame_index(source, f, file("before#{f}.png"))
      ff.frame_index(file("effect.mp4"), f, file("after#{f}.png"))
    end
    CLEAN.each { |f| expect(diff(file("before#{f}.png"), file("after#{f}.png"))).to be < 0.01, "frame #{f} should be untouched" }
    HIT.each { |fx, f| expect(diff(file("before#{f}.png"), file("after#{f}.png"))).to be > 0.015, "#{fx} at frame #{f} changed nothing" }
    expect(mean_luma(file("after49.png"))).to be < mean_luma(file("before49.png")) * 0.3
    expect(mean_luma(file("after43.png"))).to be > mean_luma(file("before43.png")) + 0.1

    # The same cues give the same picture.
    first = stream_hash(file("effect.mp4"))
    service.render
    expect(stream_hash(file("effect.mp4"))).to eq(first)

    clip = service.clip(40, 60)
    expect(ff.summary(clip).dig(:video, :frames)).to eq(20)
    expect(ff.summary(clip).dig(:audio, :codec)).to eq("aac")

    sheet = service.stills([4, 49, 75])
    expect(File.file?(sheet)).to be(true)
    expect(Dir[File.join(service.path("stills"), "*.png")].map { |p| File.basename(p) }.sort).to eq(%w[0004.png 0049.png 0075.png])
    expect(mean_luma(service.path("stills/0049.png"))).to be_within(0.02).of(mean_luma(file("after49.png")))

    config["cues"] = [{ "fx" => "sparkle", "f" => 1, "dur" => 1 }]
    File.write(File.join(dir, "cues.yml"), YAML.dump(config))
    expect { Media::Vfx.new(name).render }.to raise_error(ArgumentError, /unknown fx/)
  ensure
    FileUtils.rm_rf(File.join(RT, "prompts", name)) if name
  end

  it "rejects an unknown backend name" do
    ENV["MV_VFX"] = "metal"
    expect { Media::Vfx.backend }.to raise_error(ArgumentError, /swift or python/)
  end
end
