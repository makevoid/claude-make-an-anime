require_relative "spec_helper"

RSpec.describe "Paid ElevenLabs SFX smoke", :live, :sfx_live do
  it "generates a real effect through Media::Sfx, decodes audible WAV and reuses its cache" do
    raise "Set LIVE_FAL=1 to authorize one two-second SFX generation" unless ENV["LIVE_FAL"] == "1"
    root = File.join(RT, "tmp", "sfx-live")
    FileUtils.mkdir_p(root)
    stub_const("Media::Sfx::ROOT", root)
    Dir.chdir(root) do
      FileUtils.mkdir_p(["docs", "prompts/pop"])
      File.write("docs/PLAN.md", "SFX smoke: one two-second ElevenLabs Sound Effects v3 cartoon pop, approximately $0.004. Decode to WAV, measure signal and verify cache reuse. No paid rerolls.\n")
      Workflow::Approval.new.record!("LIVE_FAL=1 supplied by test operator")
      json_config = {"sounds" => {"pop" => {"prompt" => "One short dry cartoon cork pop, isolated, no voice or music", "duration" => 2}},
                     "cues" => [{"sound" => "pop", "at" => 0}]}
      File.write("prompts/pop/sfx.yml", YAML.dump(json_config))
      Fal::OpenAPI.fetch(Fal::Models::ElevenlabsSfx.endpoint)
      sfx = Media::Sfx.new("pop")
      sfx.generate
      summary = ff.summary(sfx.wav("pop"))
      expect(File.binread(sfx.wav("pop"), 4)).to eq("RIFF")
      expect(summary[:duration]).to be_within(0.15).of(2)
      expect(summary[:audio]).to eq(codec: "pcm_s16le", rate: 48000, channels: 2)
      pcm = ff.run("ffmpeg", "-v", "error", "-i", sfx.wav("pop"), "-f", "s16le", "-ac", "1", "-", quiet: true).unpack("s<*")
      rms = Math.sqrt(pcm.sum { |v| v.to_f ** 2 } / pcm.length) / 32768
      expect(rms).to be > 0.0001
      expect(sfx.generate(client: double("cache must not call provider"))).to eq([])
      json("verification.json", summary: summary, rms: rms, cached: true,
           generation: JSON.parse(File.read(File.join(sfx.dir, "sounds/pop.json"))))
      puts "SFX artifacts: #{root}"
    end
  end
end
