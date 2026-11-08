require_relative "spec_helper"

RSpec.describe "Seedance routing and contracts", :core do
  let(:client) { double("Fal client") }
  let(:project) { double("project", generation: {}) }
  let(:output) { { "video" => { "url" => "https://fixture/video.mp4" }, "draft_id" => "draft-fixture", "seed" => 10 } }

  def generation(spec = {})
    Pipeline::VideoGeneration.new(project: project, spec: spec, client: client)
  end

  it "keeps H3 and 768P when no provider is selected" do
    expect(client).to receive(:run).with("minimax/h3-max/image-to-video", hash_including(resolution: "768P", duration: 2.5, target_audio_url: "audio", seed: 12)).and_return(["h3", output])
    generation.generate(prompt: "move", image_url: "image", duration: 2.5, audio_url: "audio", seed: 12)
  end

  it "uses 480p Seedance, whole string seconds and no H3-only inputs" do
    expect(client).to receive(:run).with(Fal::Models::SeedanceImageToVideo.endpoint,
      { resolution: "480p", generate_audio: false, codec: "H264", prompt: "move", image_url: "image", end_image_url: "end", duration: "4", draft: true }).and_return(["seedance", output])
    g = generation("model" => "seedance", "draft" => true)
    result = g.generate(prompt: "move", image_url: "image", end_image_url: "end", duration: 2.5)
    expect(g.metadata(result)).to include(endpoint: Fal::Models::SeedanceImageToVideo.endpoint, draft_id: "draft-fixture", seed: 10)
    expect(g.seconds(4.1)).to eq(5)
  end

  it "honors scene and per-shot overrides and the environment selector" do
    ENV["VIDEO_MODEL"] = "seedance"
    expect(generation.model).to eq(Fal::Models::SeedanceImageToVideo)
    allow(project).to receive(:generation).and_return(video: { model: "seedance", resolution: "720p" })
    expect(client).to receive(:run).with(Fal::Models::SeedanceImageToVideo.endpoint, hash_including(resolution: "1080p")).and_return(["s", output])
    generation("resolution" => "1080P").generate(prompt: "move", image_url: "image", duration: 4)
    expect(generation("model" => "h3").model).to eq(Fal::Models::H3MaxImageToVideo)
  end

  it "maps dialogue to reference audio and keeps image/video references and seed" do
    expect(client).to receive(:run).with(Fal::Models::SeedanceReferenceToVideo.endpoint,
      hash_including(image_urls: ["image"], video_urls: ["video"], audio_urls: ["ambience", "voice"], seed: 42,
        duration: "4", resolution: "480p", generate_audio: true, prompt: "@Image1 speaks\n\nUse @Audio2 for the performance timing and speech.")).and_return(["r", output])
    generation("model" => "seedance", "audio" => "hero", "video_urls" => ["video"], "audio_urls" => ["ambience"]).generate(
      prompt: "@Image1 speaks", image_url: "image", audio_url: "voice", duration: 3, seed: 42)
  end

  it "completes only the saved draft at 1080p without resubmitting generation inputs" do
    ENV["VIDEO_RES"] = "480p"
    expect(client).to receive(:run).with(Fal::Models::SeedanceDraftComplete.endpoint,
      { draft_id: "draft-fixture", resolution: "1080p", codec: "H264" }).and_return(["c", output])
    generation("model" => "seedance", "draft_id" => "draft-fixture").generate
  end

  it "rejects unsupported input before a paid request even without downloaded schemas" do
    expect(client).not_to receive(:run)
    expect { generation("model" => "typo") }.to raise_error(ArgumentError, /model/)
    expect { generation("draft" => true) }.to raise_error(ArgumentError, /model: seedance/)
    expect { generation("model" => "seedance").generate(prompt: "move", image_url: "image", duration: 4, seed: 2) }.to raise_error(ArgumentError, /no seed input/)
    expect { generation("model" => "seedance", "audio" => true).generate(end_image_url: "end") }.to raise_error(ArgumentError, /no pinned end frame/)
    adapter = Fal::Models::SeedanceImageToVideo.new(client: client)
    [0, -1, 30.1, Float::INFINITY].each do |duration|
      expect { adapter.animate(prompt: "move", image_url: "image", duration: duration) }.to raise_error(ArgumentError, /duration/)
    end
    expect { adapter.animate(prompt: "move", image_url: "image", duration: 4, target_audio_url: "audio") }.to raise_error(ArgumentError, /unsupported params/)
    expect { adapter.animate(prompt: "move", image_url: "image", duration: 4, draft: true, resolution: "720p") }.to raise_error(ArgumentError, /drafts require/)
    expect { Fal::Models::SeedanceDraftComplete.new(client: client).complete(draft_id: "d", resolution: "480p") }.to raise_error(ArgumentError, /only supports 1080p/)
    expect { Fal::Models::SeedanceReferenceToVideo.new(client: client).animate(prompt: "move", duration: 4) }.to raise_error(ArgumentError, /reference files/)
  end

  it "registers all three schemas and exposes completion and provider selection through MCP" do
    require_relative "../lib/toolkit/mcp_server"
    expect(Toolkit::Operations.new.endpoints).to include(*%w[image-to-video reference-to-video draft/complete].map { |s| "bytedance/seedance-2.5/us/#{s}" })
    expect(Toolkit::CredentialTasks::TASKS).to include("seedance:complete")
    expect(Toolkit::CredentialTasks::OPTIONS).to include("VIDEO_MODEL")
  end

  it "routes single-video soundtrack guidance through the reference endpoint without H3's end-frame pin" do
    allow(project).to receive(:generation).and_return(video: { model: "seedance" })
    allow(project).to receive(:step?).with(Pipeline::Steps::RefTorn).and_return(false)
    allow(project).to receive(:fetch!).with(:ref_base, :url).and_return("image")
    allow(project).to receive(:fetch!).with(:music, :url).and_return("song")
    allow(project).to receive(:prompt).with("04_video").and_return("@Image1 sings")
    allow(project).to receive(:duration).and_return(3)
    expect(client).to receive(:run).with(Fal::Models::SeedanceReferenceToVideo.endpoint,
      hash_including(image_urls: ["image"], audio_urls: ["song"], duration: "4", resolution: "480p")).and_return(["video", output])
    Pipeline::Steps::Video.new(project: project, client: client).submit
  end

  it "completes a draft shot without requiring the original image or prompt" do
    allow(project).to receive(:generation).and_return(video: { model: "seedance" })
    allow(project).to receive(:path).with("04_shot_wave.mp4").and_return("wave.mp4")
    expect(client).to receive(:run).with(Fal::Models::SeedanceDraftComplete.endpoint,
      hash_including(draft_id: "saved", resolution: "1080p")).and_return(["complete", output])
    expect(client).to receive(:download).with("https://fixture/video.mp4", "wave.mp4").and_return("wave.mp4")
    item = Pipeline::Steps::Shots.new(project: project, client: client).generate("wave", { "frames" => 72, "draft_id" => "saved" })
    expect(item).to include(endpoint: Fal::Models::SeedanceDraftComplete.endpoint, request_id: "complete")
  end

  it "saves a standalone completion receipt and downloads its output" do
    with_workspace do
      json("complete.json", draft_id: "saved")
      allow(Fal::Client).to receive(:new).and_return(client)
      expect(client).to receive(:run).with(Fal::Models::SeedanceDraftComplete.endpoint,
        hash_including(draft_id: "saved")).and_return(["complete", output])
      expect(client).to receive(:download).with("https://fixture/video.mp4", "output/full.mp4")
      operation = Toolkit::Operations.new
      expect(operation).to receive(:emit).with(hash_including(request_id: "complete"))
      operation.call("seedance:complete", ["complete.json", "output/full.mp4"])
      expect(JSON.parse(File.read("output/full.mp4.json"))).to include("request_id" => "complete", "input" => hash_including("resolution" => "1080p"))
    end
  end

  it "accepts the observed 478-pixel 480p output in video review" do
    allow(project).to receive(:generation).and_return(video: { model: "seedance" })
    allow(project).to receive(:duration).and_return(3)
    allow(project).to receive(:step?).with(Pipeline::Steps::RefTorn).and_return(false)
    allow(project).to receive(:[]).with(:video).and_return("path" => "final", "input" => { "resolution" => "480p" })
    allow(project).to receive(:[]).with(:ref_base).and_return("path" => "reference")
    allow(project).to receive(:review_path).and_return("review")
    ffmpeg = double("FFmpeg", summary: { duration: 3, video: { w: 856, h: 478 }, audio: { codec: "aac", rate: 44_100 } },
      contact_sheet: "sheet", extract_frames: ["frame1", "frame2"])
    stats = { "images" => [{ "mono_pct" => 20, "mean_saturation" => 0.4 }], "mean_mono_pct" => 20 }
    python = double("Python", style_split: stats)
    step = Pipeline::Steps::Video.new(project: project, client: client)
    allow(step).to receive(:ffmpeg).and_return(ffmpeg)
    allow(step).to receive(:python).and_return(python)
    expect(step.review[:verdict]).to eq("PASS")
    allow(ffmpeg).to receive(:summary).and_return(duration: 3, video: { w: 640, h: 360 }, audio: { codec: "aac", rate: 44_100 })
    expect(step.review[:verdict]).to eq("REVIEW")
  end
end

RSpec.describe "Seedance shot assembly", :media do
  it "requests the four-second minimum, retains draft metadata and cuts exactly three seconds" do
    with_workspace do |dir|
      stub_const("Pipeline::ROOT", dir)
      stub_const("Pipeline::GENERATIONS", "seedance" => { frames: 72, steps: [Pipeline::Steps::Shots] })
      project = Pipeline::Project.new("seedance")
      project.record(:keyframes, items: { start: { url: "https://fixture/image.png" } })
      project.record(:music, path: tone(duration: 3))
      FileUtils.mkdir_p("prompts/seedance")
      File.write("prompts/seedance/04_shots.yml", YAML.dump([{ "name" => "wave", "model" => "seedance", "image" => "start",
        "frames" => 72, "seconds" => 3, "draft" => true, "prompt" => "A little robot waves.", "camera" => "locked" }]))
      source = ff.still_video(file("seedance-source.mp4"), frames: 96, fps: 24, color: "#112233")
      client = double("Fal client")
      expect(client).to receive(:run).with(Fal::Models::SeedanceImageToVideo.endpoint,
        hash_including(duration: "4", resolution: "480p", prompt: "A little robot waves.\n\nCamera: locked")).and_return([
          "draft-request", { "video" => { "url" => "fixture://video" }, "draft_id" => "draft-id" }])
      allow(client).to receive(:download) { |_, path| FileUtils.cp(source, path); path }
      Pipeline::Steps::Shots.new(project: project, client: client).run!
      expect(project[:shots]["items"]["wave"]).to include("draft_id" => "draft-id", "endpoint" => Fal::Models::SeedanceImageToVideo.endpoint)
      expect(ff.summary(project[:shots]["path"])).to include(duration: 3.0, video: hash_including(frames: 72, h: 1080))
    end
  end
end
