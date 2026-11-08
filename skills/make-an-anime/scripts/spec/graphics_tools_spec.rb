require_relative "spec_helper"

RSpec.describe "Deterministic graphics and asset tools", :media do
  it "renders particle frames identically alone, out of order and in sequence, with a separate light layer" do
    renderer = Media::Anim.new
    sketch = File.join(RT, "tools/p5/examples/particles.js")
    args = { width: 320, height: 180, fps: 24, frames: 18 }
    renderer.render(sketch, file("sequence"), **args)
    renderer.render(sketch, file("isolated"), **args, only: [17, 12, 0])
    [0, 12, 17].each do |frame|
      name = format("%04d.png", frame)
      expect(pixels(file("isolated/#{name}"))).to eq(pixels(file("sequence/#{name}")))
    end
    expect(pixels(file("sequence/0000.png"))).not_to eq(pixels(file("sequence/0012.png")))
    json(file("cues.json"), cues: [])
    renderer.render(sketch, file("lights"), **args, only: [12], data: { vfx: file("cues.json") })
    alpha = pixels(file("lights/0012.png")).map(&:last)
    expect(alpha.min).to eq(0)
    expect(alpha.max).to be > 0
  end

  it "cuts animation sprites through the Ruby recipe task and refuses mismatched names" do
    sheet = file("sheet.png")
    magick.run("magick", "-size", "200x100", "xc:none", "-fill", "red", "-draw", "rectangle 10,10 70,80", "-fill", "blue", "-draw", "rectangle 120,10 180,80", sheet)
    json(file("cut.json"), mode: "sprites", source: sheet, out: file("sprites"), names: %w[red blue])
    out, err, status = cli("assets:cut[#{file('cut.json')}]")
    expect(status.success?).to be(true), err
    expect(JSON.parse(out)["sprites"].keys).to eq(%w[red blue])
    expect(pixels(file("sprites/red.png"))).to include([255, 0, 0, 255])
    json(file("bad.json"), mode: "sprites", source: sheet, out: file("bad"), names: %w[red])
    _, err, status = cli("assets:cut[#{file('bad.json')}]")
    expect(status.success?).to be(false)
    expect(err).to include("found 2 sprites, expected 1")
    expect(Dir[File.join(file("bad"), "*.png")]).to be_empty
  end

  it "animates a cut-out prop over transparency with deterministic frame selection" do
    magick.run("magick", "-size", "40x60", "xc:none", "-fill", "#3090ff", "-draw", "ellipse 20,30 16,26 0,360", file("leaf.png"))
    json(file("assets.json"), sprite: "/" + file("leaf.png").delete_prefix("#{RT}/"))
    renderer = Media::Anim.new
    sketch = File.join(RT, "tools/p5/examples/sprite-motion.js")
    args = { width: 320, height: 180, fps: 24, frames: 25, data: { assets: file("assets.json") } }
    renderer.render(sketch, file("motion"), **args)
    renderer.render(sketch, file("isolated"), **args, only: [24, 0])
    [0, 24].each do |frame|
      name = format("%04d.png", frame)
      expect(pixels(file("isolated/#{name}"))).to eq(pixels(file("motion/#{name}")))
    end
    center = ->(path) do
      points = pixels(path).each_with_index.filter_map { |pixel, i| i % 320 if pixel.last > 128 }
      points.sum.fdiv(points.length)
    end
    expect(center.call(file("motion/0024.png")) - center.call(file("motion/0000.png"))).to be > 80
    expect(pixels(file("motion/0024.png")).first.last).to eq(0)
  end

  it "cuts icon grids, detects frame apertures and fits art through the recipe service" do
    sheet = file("icons.png")
    magick.run("magick", "-size", "200x100", "xc:black", "-fill", "red", "-draw", "rectangle 10,10 70,80", "-fill", "blue", "-draw", "rectangle 120,10 180,80", sheet)
    service = Media::AnimationAssets.new
    json(file("grid.json"), mode: "grid", source: sheet, out: file("icons"), names: %w[sun moon], size: 64)
    expect(service.cut(file("grid.json"))["tiles"].keys).to eq(%w[sun moon])
    magick.run("magick", "-size", "240x120", "xc:#808080", "-fill", "black", "-draw", "rectangle 20,20 100,100", file("frame.png"))
    json(file("frame.json"), mode: "frame", source: file("frame.png"), out: file("cut-frame.png"), slots: file("slots.json"), scale: 1, min_area: 100)
    expect(service.cut(file("frame.json"))["slots"]).to eq(1)
    expect(pixels(file("cut-frame.png"))[60 * 240 + 60].last).to eq(0)
    json(file("fit.json"), mode: "fit", source: sheet, out: file("background.jpg"), width: 100)
    expect(service.cut(file("fit.json"))["size"]).to eq([100, 50])
  end

  it "builds and cuts a face collage and refuses ambiguous automatic assignment" do
    red, blue = file("red.png"), file("blue.png")
    magick.run("magick", "-size", "80x80", "xc:red", red)
    magick.run("magick", "-size", "80x80", "xc:blue", blue)
    spec = { cols: 2, rows: 1, cell: [80, 80], gap: 30, margin: 20, faces: [
      { name: "pilot", sheet: red, box: [40, 40, 70] }, { name: "rival", sheet: blue, box: [40, 40, 70] }
    ] }
    json(file("faces.json"), spec)
    json(file("build.json"), mode: "build", spec: file("faces.json"), out: file("collage.png"))
    service = Media::AnimationAssets.new
    out, err, status = cli("assets:faces[#{file('build.json')}]")
    expect(status.success?).to be(true), err
    expect(JSON.parse(out)["cells"]).to eq(2)
    json(file("split.json"), mode: "cut", spec: file("faces.json"), source: file("collage.png"), out: file("faces"), size: 64)
    expect(service.faces(file("split.json"))["icons"].keys).to eq(%w[pilot rival])
    expect(pixels(file("faces/pilot.png"))).to include([255, 0, 0, 255])
    spec[:faces].pop
    json(file("faces.json"), spec)
    expect { service.faces(file("split.json")) }.to raise_error(Media::CommandError, /found 2 icons, expected 1/)
  end
end

RSpec.describe "Baked light pass", :swift do
  it "blooms only light pixels and reuses the plain picture on repeats and audio remixes" do
    run = "e2e-bake-#{Process.pid}"
    dir = File.join(RT, "output", run)
    FileUtils.mkdir_p(dir)
    final = File.join(dir, "final_overlay.mp4")
    plain = File.join(dir, "final_overlay_plain.mp4")
    ff.still_video(file("black.mp4"), frames: 24, fps: 24, color: "#101010", w: 320, h: 180)
    ff.mux(file("black.mp4"), tone(file("tone.wav")), final, shortest: true)
    prompts = File.join(RT, "prompts", "#{run}-vfx"); FileUtils.mkdir_p(prompts)
    File.write(file("light.js"), "Anim.sketch({draw(){clear();noStroke();fill('#ffffff');rect(150,80,8,8)}})")
    cfg = { source: "output/#{run}/final_overlay_plain.mp4", out: "output/#{run}/final_overlay.mp4",
            lights: file("light.js").delete_prefix("#{RT}/"), cues: [{ fx: "halo", f: 6, dur: 12, shape: "span", fade: 1, amt: 1.0, radius: 9 }] }
    File.write(File.join(prompts, "cues.yml"), YAML.dump(JSON.parse(JSON.generate(cfg))))
    bake = Media::VfxBake.new(run)
    expect(bake.bake[:reused_plain]).to be(false)
    expect(ff.summary(final).dig(:video, :frames)).to eq(24)
    expect(ff.summary(final).dig(:audio, :codec)).to eq("aac")
    first = bake.send(:video_hash, final)
    ff.frame_index(final, 10, file("glow.png"))
    ff.frame_index(plain, 10, file("plain.png"))
    # A region outside the 8px source light brightens; a far corner is preserved.
    crop_luma = ->(path, box) { magick.run("magick", path, "-crop", box, "-colorspace", "gray", "-format", "%[fx:mean]", "info:", quiet: true).to_f }
    expect(crop_luma.call(file("glow.png"), "12x12+135+77")).to be > crop_luma.call(file("plain.png"), "12x12+135+77") + 0.01
    expect(crop_luma.call(file("glow.png"), "20x20+0+0")).to be_within(0.02).of(crop_luma.call(file("plain.png"), "20x20+0+0"))
    expect(bake.bake[:reused_plain]).to be(true)
    expect(bake.send(:video_hash, final)).to eq(first)
    # Remux only audio, then bake again: the video must remain unchanged.
    ff.run("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=300:duration=1", file("new.wav"))
    ff.mux(final, file("new.wav"), file("remix.mp4"), shortest: false)
    FileUtils.cp(file("remix.mp4"), final)
    expect(bake.bake[:reused_plain]).to be(true)
    expect(bake.send(:video_hash, final)).to eq(first)
    # An invalid cue leaves the delivered overlay intact.
    cfg[:cues][0][:fx] = "unknown"
    File.write(File.join(prompts, "cues.yml"), YAML.dump(JSON.parse(JSON.generate(cfg))))
    before = Digest::SHA256.file(final).hexdigest
    expect { bake.bake }.to raise_error(ArgumentError, /unknown fx/)
    expect(Digest::SHA256.file(final).hexdigest).to eq(before)
  end
end
