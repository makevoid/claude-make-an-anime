require_relative "spec_helper"

RSpec.describe "Production fixes", :core do
  it "budgets skipped frames into H3 duration" do
    shots = Pipeline::Steps::Shots.new
    expect(shots.send(:default_seconds, { "frames" => 72, "skip_frames" => 2 })).to eq(3.1)
    expect(shots.send(:default_seconds, { "frames" => 24, "audio" => "pilot" })).to eq(2.0)
  end

  it "refuses a short source before assembling a truncated plate" do
    shots = Pipeline::Steps::Shots.new
    ffmpeg = double
    allow(shots).to receive(:ffmpeg).and_return(ffmpeg)
    allow(shots).to receive(:specs).and_return("run" => { "frames" => 72, "skip_frames" => 2 })
    allow(ffmpeg).to receive(:summary).and_return(video: { frames: 73 })
    expect(ffmpeg).not_to receive(:concat_shots)
    expect { shots.send(:finish, "run" => { "path" => "take.mp4" }) }.to raise_error(ArgumentError, /run: source has 73 frames; needs 74/)
  end

  it "does not mistake running water for a runner, but still catches a person running near it" do
    rules = Pipeline::Believability
    expect(rules.shot_problems("sink", { "prompt" => "Water is running from the tap.", "camera" => "locked" })).to be_empty
    expect(rules.shot_problems("sink", { "prompt" => "He watches the running water.", "camera" => "locked" })).to be_empty
    expect(rules.shot_problems("chase", { "prompt" => "Water is running. She runs past the sink.", "camera" => "locked" })).not_to be_empty
  end

  it "reports gated speech at its audible start and keeps legacy line timing" do
    with_workspace do |dir|
      stub_const("Pipeline::ROOT", dir)
      stub_const("Pipeline::GENERATIONS", "gated" => { frames: 48, steps: [Pipeline::Steps::Shots] })
      project = Pipeline::Project.new("gated")
      FileUtils.mkdir_p("prompts/gated")
      File.write("prompts/gated/04_shots.yml", YAML.dump([
        { "name" => "pause", "color" => "#000000", "frames" => 24 },
        { "name" => "line", "image" => "pilot", "frames" => 24, "audio" => "pilot" }
      ]))
      json(project.path("03_dialogue_lines.json"), [{ name: "hello", character: "pilot", at: 0.8, speech_at: 1.1, end: 1.8 }])
      result = Toolkit::AnimeReview.new(project).timeline
      expect(result[:ok]).to be(true)
      expect(result[:shots][0][:lines]).to be_empty
      expect(result[:shots][1][:lines]).to eq(["hello 1.10–1.80"])
      json(project.path("03_dialogue_lines.json"), [{ name: "hello", character: "pilot", at: 0.8, end: 1.8 }])
      expect(Toolkit::AnimeReview.new(project).timeline[:issues].join).to include("crosses a cut")
    end
  end
end

RSpec.describe "Local take and mix reuse", :media do
  it "copies an existing take without Fal, catches short trims, and refreshes a replaced source" do
    with_workspace do |dir|
      stub_const("Pipeline::ROOT", dir)
      stub_const("Pipeline::GENERATIONS", "dest" => { frames: 12, steps: [Pipeline::Steps::Shots] })
      source = Pipeline::Project.new("source")
      movie = video(file("original.mp4"))
      source.record(:shots, items: { saved: { path: movie } })
      dest = Pipeline::Project.new("dest")
      dest.record(:music, path: tone(file("bed.wav")))
      FileUtils.mkdir_p("prompts/dest")
      spec = { "name" => "replay", "from_take" => "source/saved", "frames" => 12, "skip_frames" => 6 }
      File.write("prompts/dest/04_shots.yml", YAML.dump([spec]))
      step = Pipeline::Steps::Shots.new(project: dest)
      expect(Fal::Client).not_to receive(:new)
      step.run!
      item = dest[:shots]["items"]["replay"]
      expect(item).to include("adopted" => true, "from_take" => "source/saved")
      expect(File.binread(item["path"])).to eq(File.binread(movie))
      expect(ff.summary(dest[:shots]["path"]).dig(:video, :frames)).to eq(12)
      expect(step.stale_item?("replay", spec, item)).to be(false)
      ff.still_video(movie, frames: 24, fps: 24, color: "#0000ff")
      expect(step.stale_item?("replay", spec, item)).to be(true)
      step.run!
      expect(File.binread(dest[:shots]["items"]["replay"]["path"])).to eq(File.binread(movie))
      expect { step.send(:generate, "bad", spec.merge("skip_frames" => 20)) }.to raise_error(ArgumentError, /needs 32/)
      expect { step.send(:generate, "bad", spec.merge("from_take" => "../saved")) }.to raise_error(ArgumentError, /from_take must/)
    end
  end

  it "remixes changed settings or same-mtime source bytes and refuses a stale soundtrack" do
    with_workspace do |dir|
      stub_const("Pipeline::ROOT", dir)
      stub_const("Pipeline::GENERATIONS", "mix" => { frames: 48, steps: [Pipeline::Steps::Mix] })
      project = Pipeline::Project.new("mix")
      source = tone(file("score.wav"))
      project.record(:music, path: source)
      step = Pipeline::Steps::Mix.new(project: project)
      step.run!
      expect(project[:mix]["input"]["music_db"]).to eq(-12)
      first = Digest::SHA256.file(project[:mix]["path"]).hexdigest
      Pipeline::GENERATIONS["mix"][:mix] = { music_db: -6 }
      expect { project.soundtrack }.to raise_error(/mix missing or stale/)
      step.run!
      expect(Digest::SHA256.file(project.soundtrack).hexdigest).not_to eq(first)
      mtime = File.mtime(source)
      ff.run("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=300:duration=2", "-ac", "2", source)
      File.utime(mtime, mtime, source)
      expect(step.done?).to be(false)
      step.run!
      expect(step.done?).to be(true)
      project.record(:dialogue, path: tone(file("voice.wav")))
      expect { project.soundtrack }.to raise_error(/run gen:mix/)
    end
  end

  it "drops the requested prefix before retiming with or without an explicit source length" do
    ff.still_video(file("red.mp4"), frames: 12, fps: 24, color: "#ff0000", w: 64, h: 64)
    ff.still_video(file("blue.mp4"), frames: 12, fps: 24, color: "#0000ff", w: 64, h: 64)
    ff.concat_shots([{ path: file("red.mp4"), frames: 12 }, { path: file("blue.mp4"), frames: 12 }], file("take.mp4"), fps: 24)
    [nil, 12].each_with_index do |keep, i|
      out = file("retimed-#{i}.mp4")
      ff.concat_shots([{ path: file("take.mp4"), skip: 12, keep: keep, retime: true, frames: 24 }], out, fps: 24)
      expect(ff.summary(out).dig(:video, :frames)).to eq(24)
      ff.frame_index(out, 0, file("first-#{i}.png"))
      red, _, blue = pixels(file("first-#{i}.png")).first
      expect(blue).to be > red + 100
    end
  end

  it "muffles a voice locally without changing its duration or source" do
    source = file("bright.wav")
    ff.run("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=5000:duration=1", "-ac", "2", source)
    before = Digest::SHA256.file(source).hexdigest
    dry = ff.place_audio([{ "path" => source, "at" => 0 }], file("dry.wav"), seconds: 1)
    wet = ff.place_audio([{ "path" => source, "at" => 0, "muffled" => true }], file("wet.wav"), seconds: 1)
    rms = ->(path) { py.audio_energy(path)["windows"].map { |w| w["rms_db"] }.max }
    expect(rms.call(wet)).to be < rms.call(dry) - 15
    expect(ff.duration(wet)).to be_within(0.01).of(1)
    expect(Digest::SHA256.file(source).hexdigest).to eq(before)
  end
end
