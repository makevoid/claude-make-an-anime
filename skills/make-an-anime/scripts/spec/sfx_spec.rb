require_relative "spec_helper"

RSpec.describe Fal::Models::ElevenlabsSfx, :core do
  it "maps toolkit arguments to the v3 schema without unsupported legacy fields" do
    client = double("Fal client")
    expect(client).to receive(:run).with("elevenlabs/sound-effects/v3", {
      text: "One dry pop", duration_seconds: 2, prompt_influence: 0.3,
      loop: false, output_format: "mp3_44100_128"
    }).and_return(["request-1", {"audio" => {"url" => "https://fixture.test/pop.mp3"}}])
    expect(described_class.new(client: client).generate(prompt: "One dry pop").request_id).to eq("request-1")
  end

  it "rejects invalid prompts, durations and controls before a paid call" do
    model = described_class.new(client: double("unused client"))
    [{prompt: ""}, {prompt: "a" * 451}, {duration: 0.4}, {duration: 31},
     {prompt_influence: 1.1}, {loop: "true"}].each do |invalid|
      expect { model.generate(**{prompt: "A bell"}.merge(invalid)) }.to raise_error(ArgumentError)
    end
  end
end

RSpec.describe Media::Sfx, :media do
  it "decodes MP3 into WAV, replaces legacy cache, caches v3 output and repeats long ambience" do
    with_workspace do |root|
      stub_const("Media::Sfx::ROOT", root)
      FileUtils.mkdir_p("prompts/test")
      spec = {"prompt" => "Rain", "duration" => 2, "seed" => 7, "negative" => "voices"}
      config = {"sounds" => {"rain" => spec}, "cues" => [{"sound" => "rain", "at" => 0}]}
      File.write("prompts/test/sfx.yml", YAML.dump(config))
      sfx = described_class.new("test")
      tone(sfx.wav("rain"), duration: 2)
      meta = File.join(sfx.dir, "sounds/rain.json")
      json(meta, prompt: "Rain", duration: 2, seed: 7, negative_prompt: "voices")
      encoded = File.join(root, "fixture.mp3")
      ff.run("ffmpeg", "-y", "-v", "error", "-i", sfx.wav("rain"), encoded)
      inputs = []
      client = double("Fal client")
      allow(client).to receive(:run) do |endpoint, input|
        expect(endpoint).to eq("elevenlabs/sound-effects/v3")
        inputs << input
        ["request-#{inputs.length}", {"audio" => {"url" => "https://fixture.test/rain.mp3"}}]
      end
      allow(client).to receive(:download) { |_url, path| FileUtils.cp(encoded, path); path }

      expect(sfx.generate(client: client)).to eq(["rain"])
      expect(inputs.first[:text]).to eq("Rain. Avoid: voices")
      expect(inputs.first.keys).not_to include(:seed, :negative_prompt, :duration, :prompt)
      expect(File.binread(sfx.wav("rain"), 4)).to eq("RIFF")
      expect(ff.summary(sfx.wav("rain"))[:audio]).to eq(codec: "pcm_s16le", rate: 48000, channels: 2)
      expect(sfx.generate(client: client)).to eq([])
      expect(inputs.length).to eq(1)
      expect(JSON.parse(File.read(meta))["model"]).to eq("elevenlabs/sound-effects/v3")

      sfx.sounds["rain"].merge!("duration" => 47, "loop" => true, "prompt_influence" => 0.5)
      expect(sfx.generate(client: client)).to eq(["rain"])
      expect(inputs.last).to include(duration_seconds: 30, loop: true, prompt_influence: 0.5)
      expect(ff.duration(sfx.wav("rain"))).to be_within(0.01).of(47)
      expect(sfx.generate(client: client)).to eq([])
    end
  end
end
