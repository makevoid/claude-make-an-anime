require_relative "spec_helper"

RSpec.describe "Episode tools: modular generations and scene scaffold", :core do
  it "merges config/generations.rb with config/generations/*.rb and rejects a run defined twice" do
    Dir.mktmpdir("gen-") do |root|
      FileUtils.mkdir_p(File.join(root, "config", "generations"))
      File.write(File.join(root, "config", "generations.rb"), %({ "char-a" => { steps: [Steps::RefBase] } }))
      File.write(File.join(root, "config", "generations", "ep01-s02.rb"), %({ "ep01-s02" => { steps: [Steps::Shots], **scene(48) } }))
      runs = Pipeline::GenerationConfig.new(root).load
      expect(runs.keys).to eq(%w[char-a ep01-s02])
      expect(runs["ep01-s02"]).to include(frames: 48, steps: [Pipeline::Steps::Shots])
      File.write(File.join(root, "config", "generations", "dup.rb"), %({ "char-a" => {} }))
      expect { Pipeline::GenerationConfig.new(root).load }.to raise_error(ArgumentError, /char-a is defined in both/)
    end
  end

  it "scaffolds a scene whose generation, shot frames and score length agree, and never overwrites" do
    Dir.mktmpdir("scene-") do |root|
      episode = Toolkit::Episode.new(root: root)
      out = episode.scaffold("ep01-s02", 480)
      expect(out[:seconds]).to eq(20.0)
      gen = Pipeline::GenerationConfig.new(root).load.fetch("ep01-s02")
      expect(gen[:frames]).to eq(480)
      expect(gen[:mix][:music_end]).to eq(20.0)
      shots = YAML.safe_load_file(File.join(root, "prompts", "ep01-s02", "04_shots.yml"))
      expect(shots.sum { _1["frames"] }).to eq(480)
      score = JSON.parse(File.read(File.join(root, "prompts", "ep01-s02", "03_score.json")))
      expect(score["chunks"].sum { _1["duration_ms"] }).to eq(20_000)
      expect(YAML.safe_load_file(File.join(root, "prompts", "ep01-s02-sfx", "sfx.yml"))["out"]).to eq("output/ep01-s02/final_sfx.mp4")
      expect { episode.scaffold("ep01-s02", 480) }.to raise_error(ArgumentError, /already exists/)
      expect(episode.runs_for("ep01")).to eq(["ep01-s02"])
    end
  end

  it "plays scenes in the order of config/episodes/<prefix>.yml when it exists" do
    Dir.mktmpdir("order-") do |root|
      FileUtils.mkdir_p(File.join(root, "config", "episodes"))
      File.write(File.join(root, "config", "episodes", "ep01.yml"), %w[ep01-s02 ep01-s04 ep01-s03].to_yaml)
      expect(Toolkit::Episode.new(root: root).runs_for("ep01")).to eq(%w[ep01-s02 ep01-s04 ep01-s03])
    end
  end
end

RSpec.describe "Prompt YAML with the style bible", :core do
  it "expands {{STYLE}} after parsing, so a style with quotes and colons cannot break a quoted scalar" do
    Dir.mktmpdir("style-") do |root|
      stub_const("Pipeline::ROOT", root)
      FileUtils.mkdir_p([File.join(root, "config"), File.join(root, "prompts", "ep01-s09")])
      File.write(File.join(root, "config", "style.md"), "Keep the real person's likeness: cel shading, no text.")
      # A single-quoted scalar (what Psych writes for text with double quotes) broke when the raw file was expanded.
      File.write(File.join(root, "prompts", "ep01-s09", "02_keyframes.yml"), "k:\n  prompt: '{{STYLE}} The boy''s snack \"thanks\"'\n")
      step = Pipeline::Steps::Keyframes.new(project: Pipeline::Project.new("ep01-s09"))
      expect(step.send(:yaml, "02_keyframes")["k"]["prompt"]).to eq(%(Keep the real person's likeness: cel shading, no text. The boy's snack "thanks"))
    end
  end
end

RSpec.describe "Episode preview", :media do
  it "joins each scene's most finished file in order and reports a scene with no final" do
    Dir.mktmpdir("ep-") do |root|
      a = File.join(root, "output", "ep01-s01"); b = File.join(root, "output", "ep01-s02")
      FileUtils.mkdir_p([a, b, File.join(root, "prompts", "ep01-s01"), File.join(root, "prompts", "ep01-s02")])
      img = character(file("ep.png"), width: 320, height: 180)
      ff.still_plate(img, tone(file("ep1.wav"), duration: 1), File.join(a, "final_overlay.mp4"), seconds: 1, w: 320, h: 180)
      ff.still_plate(img, tone(file("ep2.wav"), duration: 2), File.join(a, "final_sfx.mp4"), seconds: 2, w: 320, h: 180)
      episode = Toolkit::Episode.new(root: root)
      expect { episode.preview("output/p.mp4", ["ep01"]) }.to raise_error(ArgumentError, /ep01-s02/)
      quiet = ff.run("ffmpeg", "-y", "-v", "error", "-i", tone(file("ep3.wav"), duration: 1), "-af", "volume=-10dB", file("ep3q.wav"), quiet: true) && file("ep3q.wav")
      ff.still_plate(img, quiet, File.join(b, "final.mp4"), seconds: 1, w: 320, h: 180)
      out = episode.preview("output/p.mp4", ["ep01"])
      expect(out[:scenes].map { _1[:file] }).to eq(["output/ep01-s01/final_sfx.mp4", "output/ep01-s02/final.mp4"])
      expect(out[:seconds]).to be_within(0.1).of(3.0)
      # Each scene is moved to -23 LUFS: the 10 dB quieter scene gets ~10 dB more gain.
      out[:scenes].each { |sc| expect(sc[:lufs] + sc[:gain_db]).to be_within(0.5).of(-23.0) }
      expect(out[:scenes][1][:gain_db] - out[:scenes][0][:gain_db]).to be_within(1.5).of(10.0)
      expect(ff.loudness(File.join(root, "output", "p_leveled", "ep01-s02.mp4"))[:lufs]).to be_within(1.0).of(-23.0)

      # VFX beats in scene frames land on film frames, and `end` is the cut into the next scene.
      FileUtils.mkdir_p(File.join(root, "prompts", "ep01-vfx"))
      File.write(File.join(root, "prompts", "ep01-vfx", "beats.yml"), YAML.dump(
        "episode" => "ep01", "source" => "a.mp4", "out" => "b.mp4",
        "beats" => [{ "run" => "ep01-s02", "f" => 3, "fx" => "punch", "dur" => 2 }, { "run" => "ep01-s01", "f" => "end", "fx" => "dark", "dur" => 2 }]
      ))
      episode.vfx_cues("ep01-vfx")
      first = ff.summary(File.join(a, "final_sfx.mp4")).dig(:video, :frames)
      cues = YAML.safe_load_file(File.join(root, "prompts", "ep01-vfx", "cues.yml"))["cues"]
      expect(cues.map { _1["f"] }).to eq([first + 3, first])
    end
  end

  it "levels a scene with speech by its voices, and one without by its loudness" do
    Dir.mktmpdir("voice-") do |root|
      a = File.join(root, "output", "ep01-s01"); b = File.join(root, "output", "ep01-s02")
      FileUtils.mkdir_p([a, b, File.join(root, "prompts", "ep01-s01"), File.join(root, "prompts", "ep01-s02")])
      img = character(file("v.png"), width: 320, height: 180)
      ff.still_plate(img, tone(file("v1.wav"), duration: 2), File.join(a, "final_sfx.mp4"), seconds: 2, w: 320, h: 180)
      ff.still_plate(img, tone(file("v2.wav"), duration: 2), File.join(b, "final_sfx.mp4"), seconds: 2, w: 320, h: 180)
      File.write(File.join(a, "03_dialogue_lines.json"), JSON.generate([{ "at" => 0.2, "end" => 1.8, "vo" => true }]))
      out = Toolkit::Episode.new(root: root).preview("output/p.mp4", ["ep01"], voice_db: -24.0)
      with, without = out[:scenes]
      expect(with[:speech_db] + with[:gain_db]).to be_within(0.5).of(-24.0)
      expect(without[:speech_db]).to be_nil
      expect(without[:lufs] + without[:gain_db]).to be_within(0.5).of(-23.0)
    end
  end

  it "fades each scene's track around its voices, leaves the film's ends and a silent card alone, and ignores laughs and thoughts when levelling" do
    Dir.mktmpdir("seam-") do |root|
      runs = %w[ep01-s01 ep01-s02 ep01-s03 ep01-s04]
      dirs = runs.map { File.join(root, "output", _1) }
      FileUtils.mkdir_p(dirs + runs.map { File.join(root, "prompts", _1) })
      img = character(file("s.png"), width: 320, height: 180)
      silence = file("s_silence.wav")
      ff.run("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "2", silence, quiet: true)
      ff.still_plate(img, silence, File.join(dirs[0], "final_sfx.mp4"), seconds: 2, w: 320, h: 180)
      dirs[1..2].each_with_index { |dir, i| ff.still_plate(img, tone(file("s#{i}.wav"), duration: 4), File.join(dir, "final_sfx.mp4"), seconds: 4, w: 320, h: 180) }
      ff.still_plate(img, tone(file("s9.wav"), duration: 2), File.join(dirs[3], "final_sfx.mp4"), seconds: 2, w: 320, h: 180)
      File.write(File.join(dirs[1], "03_dialogue_lines.json"), JSON.generate([
        { "at" => 1.0, "end" => 2.0 }, { "at" => 2.0, "end" => 2.5, "subtitle" => " " }, { "at" => 2.5, "end" => 3.0, "vo" => true, "inner" => true }
      ]))
      out = Toolkit::Episode.new(root: root).preview("output/p.mp4", ["ep01"], voice_db: -24.0, seams: true)
      card, spoken, plain, ending = out[:scenes]
      expect(card[:gain_db]).to eq(0.0)
      expect(card[:fade_in]).to be_nil
      expect(spoken[:fade_out]).to be_within(0.01).of(0.88) # the air after the last line, kept 0.12 s off it
      expect(spoken[:speech_db]).not_to be_nil
      expect(plain[:fade_out]).to eq(1.4)
      expect(ending[:fade_out]).to eq(0)
    end
  end

  it "rings a score out past its end without touching what comes before, and keeps a mix without the voice lift" do
    music = tone(file("ring.wav"), duration: 3)
    out = ff.ring_out(music, file("ring_out.wav"), tail: 1.5)
    expect(ff.duration(out)).to be_within(0.05).of(4.5)
    voice = tone(file("voice.wav"), duration: 1)
    plain = ff.duck_mix(music, voice, file("plain.wav"), seconds: 3, duck: false, music_db: -60, dialogue_db: 0)
    lifted = ff.duck_mix(music, voice, file("lift.wav"), seconds: 3, duck: false, music_db: -60, dialogue_db: 6)
    expect(ff.loudness(lifted)[:lufs]).to be > ff.loudness(plain)[:lufs] + 3
  end

  it "silences the score in a music gap with a hard cut, whatever music_out the end of the film uses" do
    music = tone(file("gap_music.wav"), duration: 4)
    out = ff.duck_mix(music, nil, file("gap.wav"), seconds: 4, music_db: 0, music_end: 4, music_out: 1.0, music_gaps: [[1.0, 2.0]], music_back: 0.1)
    level = py.audio_energy(out)["windows"]
    at = ->(from, to) { level.select { |w| w["t"] >= from && w["t"] < to }.map { _1["rms_db"] } }
    before, inside, after = at.(0.2, 0.7), at.(1.2, 1.8), at.(2.3, 2.8)
    expect(inside.max).to be < -60
    expect(before.min).to be > -40 # not already fading towards the gap
    expect(after.min).to be_within(1).of(before.min) # and back at full level after it
  end
end
