require_relative "spec_helper"
require_relative "support/synthetic_anime_fal"
# Anime scene path with deterministic synthetic provider I/O: cast voices -> placed dialogue + per-character mouth tracks ->
# ElevenLabs score -> ducked mix -> shots (H3 with camera + character voice, held still, colour insert) -> 1080p plate.

RSpec.describe "Anime scene pipeline", :media do
  it "voices a cast, ducks the score under it and builds a camera-directed shot edit at 1080p" do
    image = character(file("kf.png"), width: 1920, height: 1080)
    voice = tone(file("voice.wav"), duration: 1.5)
    music = tone(file("music.wav"), duration: 4)
    movie = ff.still_plate(image, music, file("h3.mp4"), seconds: 3, w: 1366, h: 768)
    run = "anime-scene-#{Process.pid}"
    steps = Pipeline::Steps
    stub_const("Pipeline::GENERATIONS", { run => { steps: [steps::Dialogue, steps::Music, steps::Mix, steps::Keyframes, steps::Shots],
                                                   **Pipeline.scene(96), mix: { music_end: 3.5 } } })
    project = Pipeline::Project.new(run)
    prompts = File.join(RT, "prompts", run); FileUtils.mkdir_p(prompts)
    File.write(File.join(prompts, "03_dialogue.yml"), YAML.dump([
      { "name" => "kid", "character" => "kid", "at" => 0.25, "text" => "[sleepy] hello there" },
      { "name" => "narrator", "character" => "dad", "at" => 2.0, "text" => "hello there", "vo" => true }
    ]))
    File.write(File.join(prompts, "03_score.json"), JSON.generate(chunks: [{ text: "[Instrumental]", duration_ms: 3500, positive_styles: ["soft piano"] }]))
    File.write(File.join(prompts, "02_keyframes.yml"), YAML.dump("bed" => { "base" => false, "prompt" => "{{STYLE}} Kid in bed" }))
    File.write(File.join(prompts, "04_shots.yml"), YAML.dump([
      { "name" => "talk", "image" => "bed", "frames" => 48, "audio" => "kid", "prompt" => "{{STYLE}} The kid lifts his head and talks.",
        "camera" => { "move" => "slow dolly-in", "from" => "medium shot", "to" => "medium close-up", "timing" => "0-2s, ease-out" } },
      { "name" => "hold", "still" => "bed", "frames" => 24, "zoom" => [1.0, 1.04] },
      { "name" => "screen", "color" => "#05070a", "frames" => 24 }
    ]))
    client = SyntheticAnimeFal.new(image: image, video: movie, voice: voice, music: music)
    with_workspace do |dir|
      stub_const("Pipeline::ROOT", RT)
      FileUtils.mkdir_p(File.join(RT, "config"))
      cast = File.join(RT, "config", "cast.yml")
      style = File.join(RT, "config", "style.md")
      saved = [cast, style].to_h { [_1, File.file?(_1) ? File.read(_1) : nil] } # RT is the real project: put its files back
      File.write(cast, YAML.dump("kid" => { "voice" => "Jessica", "stability" => 0.35 }, "dad" => { "voice" => "Brian" }))
      File.write(style, "Clean cel-shaded TV anime.")
      begin
        approve
        steps::Dialogue.new(project: project, client: client).run!
        steps::Music.new(project: project, client: client).run!
        steps::Mix.new(project: project, client: client).run!
        steps::Keyframes.new(project: project, client: client).run!
        steps::Shots.new(project: project, client: client).run!
        # A held still or colour insert whose spec changed is rebuilt locally without FORCE.
        File.write(File.join(prompts, "04_shots.yml"), YAML.dump(YAML.load_file(File.join(prompts, "04_shots.yml")).map do |sh|
          { "hold" => sh.merge("frames" => 12), "screen" => sh.merge("frames" => 36, "color" => "#ffffff") }.fetch(sh["name"], sh)
        end))
        steps::Shots.new(project: project, client: client).run!
        screen = project[:shots]["items"]["screen"]["path"]
        @local = [ff.summary(screen).dig(:video, :frames), ff.summary(project[:shots]["items"]["hold"]["path"]).dig(:video, :frames)]
        # A music retake makes the mix stale: Mix rebuilds it without FORCE.
        mix = steps::Mix.new(project: project, client: client)
        @fresh = mix.done?
        File.utime(Time.now - 60, Time.now - 60, project[:mix]["path"])
        @stale = !mix.done?
        mix.run!
        @rebuilt = mix.done?
        # A shaped score set with music_from after gen:music makes the fit stale: Music re-fits from it locally.
        Pipeline::GENERATIONS[run][:music_from] = music
        score = steps::Music.new(project: project, client: client)
        @music_stale = !score.done?
        score.run!
        @refit = [score.done?, project[:music]["endpoint"], mix.done?]
        review = Toolkit::AnimeReview.new(project)
        @timeline, @cam = review.timeline, review.camera
      ensure
        saved.each { |path, body| body ? File.write(path, body) : FileUtils.rm_f(path) }
      end
    end
    tts = client.calls.select { |e, _| e == Fal::Models::ElevenTtsV4.endpoint }
    expect(tts.map { |_, i| i[:voice] }).to eq(%w[Jessica Brian])
    expect(tts.first[1]).to include(stability: 0.35, timestamps: true)
    expect(client.calls.map(&:first)).to include(Fal::Models::ElevenMusic25.endpoint)
    d = project[:dialogue]
    expect(ff.duration(d["path"])).to be_within(0.03).of(4.0)
    expect(d["tracks"].keys).to contain_exactly("kid", "dad")
    words = JSON.parse(File.read(d["words"]))
    expect(words.first).to include("w" => "hello", "s" => 0.35, "character" => "kid")
    # The narrator is voice-over: the dad's mouth track stays silent where his line plays.
    dad = py.audio_energy(ff.to_wav(d["tracks"]["dad"], file("dad.wav")))
    expect(dad["windows"].map { |w| w["rms_db"] }.max).to be < -60
    expect(ff.duration(project[:mix]["path"])).to be_within(0.03).of(4.0)
    expect([@fresh, @stale, @rebuilt]).to eq([true, true, true])
    expect(@music_stale).to be(true)
    expect(@refit).to eq([true, "local:#{music}", false])
    kf = client.calls.find { |e, _| e == Fal::Models::GptImage26Edit.endpoint }
    expect(kf[1][:prompt]).to eq("Clean cel-shaded TV anime. Kid in bed")
    h3 = client.calls.select { |e, _| e.include?("image-to-video") }
    expect(h3.size).to eq(1) # still and colour shots make no model call, also when rebuilt after a spec change
    expect(@local).to eq([36, 12])
    expect(h3.first[1]).to include(resolution: "768P", duration: 2.0)
    expect(h3.first[1][:prompt]).to end_with("Camera: move: slow dolly-in; from: medium shot; to: medium close-up; timing: 0-2s, ease-out")
    expect(h3.first[1][:prompt]).to start_with("Clean cel-shaded TV anime. The kid")
    expect(client.uploads.last).to end_with("04_voice_talk.wav")
    final = ff.summary(project[:shots]["path"])
    expect(final.dig(:video, :frames)).to eq(96)
    expect([final.dig(:video, :w), final.dig(:video, :h)]).to eq([1920, 1080])
    timeline, cam = @timeline, @cam
    expect(timeline).to include(ok: true, frames: 96)
    expect(timeline[:shots].first).to include(shot: "talk", audio: "kid")
    expect(timeline[:shots].first[:lines].first).to start_with("kid ")
    expect(cam.map { _1[:shot] }).to eq(["talk"]) # still and colour shots have no camera to measure
    expect(cam.first).to include(measured: "static (no measurable camera move)", directed: "slow dolly-in")
    expect(cam.first[:hint]).to start_with("MISMATCH")
  end

  it "flags a talking shot whose speaker's line crosses the cut" do
    run = "anime-timeline-#{Process.pid}"
    stub_const("Pipeline::GENERATIONS", { run => { steps: [Pipeline::Steps::Shots], **Pipeline.scene(48) } })
    project = Pipeline::Project.new(run)
    prompts = File.join(RT, "prompts", run); FileUtils.mkdir_p(prompts)
    File.write(File.join(prompts, "04_shots.yml"), YAML.dump([
      { "name" => "a", "image" => "x", "frames" => 24, "audio" => "kid" },
      { "name" => "b", "image" => "x", "frames" => 24, "audio" => "dad" }
    ]))
    File.write(project.path("03_dialogue_lines.json"), JSON.generate([
      { "name" => "kid-line", "character" => "kid", "at" => 0.2, "end" => 1.4 },
      { "name" => "dad-line", "character" => "dad", "at" => 1.5, "end" => 1.9, "vo" => true }
    ]))
    t = Toolkit::AnimeReview.new(project).timeline
    expect(t[:ok]).to be(false)
    expect(t[:issues].join("\n")).to include("kid-line", "crosses", "b: audio dad but none of their on-screen lines")
    expect(t[:shots].first[:min_frames_for_lines]).to eq(40)
  end

  it "measures a push-in and a pan between two frames" do
    with_workspace do
      first = file("cam0.png")
      magick.run("magick", "-seed", "7", "-size", "960x540", "plasma:", "-blur", "0x2", first)
      magick.run("magick", first, "-gravity", "center", "-crop", "800x450+0+0", "+repage", "-resize", "960x540!", file("push.png"))
      magick.run("magick", first, "-crop", "840x540+120+0", "+repage", "-resize", "960x540!", file("pan.png"))
      push = py.camera_motion(first, file("push.png"))
      expect(push["zoom"]).to be_within(0.03).of(1.2)
      expect(push["camera"]).to start_with("push-in")
      pan = py.camera_motion(first, file("pan.png"))
      expect(pan["camera"]).to include("pan right")
    end
  end

  it "parses ElevenLabs character alignment into word cues and strips audio tags for review" do
    words = Pipeline::Steps::Dialogue.words({ "characters" => "Hi you".chars,
                                               "character_start_times_seconds" => [0, 0.1, 0.2, 0.3, 0.4, 0.5],
                                               "character_end_times_seconds" => [0.1, 0.2, 0.3, 0.4, 0.5, 0.6] })
    expect(words).to eq([{ "w" => "Hi", "s" => 0.0, "e" => 0.2 }, { "w" => "you", "s" => 0.3, "e" => 0.6 }])
    expect(Pipeline::Steps::Dialogue.spoken("[sleepy] Papa… are you making a game?")).to eq(%w[papa are you making a game])
    # A doubled phrase is extra even though each word is in the script.
    d = Pipeline::Steps::Dialogue
    want = d.spoken("Software should be free — free as in freedom.")
    expect(d.word_diff(want, d.spoken("Software should be free. Software should be free — free as in freedom."))).to eq([[], %w[software should be free]])
    expect(d.word_diff(want, d.spoken("Software should be free as in freedom"))).to eq([%w[free], []])
  end

  it "joins streamed alignment chunks that split a word" do
    chunk = ->(chars, t0) { { "characters" => chars, "character_start_times_seconds" => chars.each_index.map { t0 + _1 * 0.1 },
                              "character_end_times_seconds" => chars.each_index.map { t0 + _1 * 0.1 + 0.1 } } }
    words = Pipeline::Steps::Dialogue.words([chunk.(["G", "o", " ", "M"], 0.0), chunk.(["i", "n", "e"], 0.4)])
    expect(words.map { _1["w"] }).to eq(%w[Go Mine])
    expect(words.last).to include("s" => be_within(1e-9).of(0.3), "e" => be_within(1e-9).of(0.7))
  end

  it "drops performed audio tags and punctuation-only tokens from subtitle cues" do
    words = [["[sleepy,", 0, 0.14], ["mumbling]", 0.16, 0.22], ["Papa", 0.24, 0.8], ["…", 0.8, 1.28], ["game?", 2.4, 3.04], ["[laughs]Ok", 3.1, 3.4]]
              .map { |w, s, e| { "w" => w, "s" => s, "e" => e } }
    expect(Pipeline::Steps::Dialogue.spoken_words(words).map { _1["w"] }).to eq(["Papa", "game?", "Ok"])
  end

end

RSpec.describe "Reused takes and Whisper language", :core do
  it "reuses the footage of an earlier generated shot and refuses anything else" do
    specs = { "bite" => { "image" => "a", "frames" => 96 }, "held" => { "still" => "a", "frames" => 24 },
              "again" => { "same_take" => "bite", "skip_frames" => 29, "frames" => 60 },
              "bad_still" => { "same_take" => "held", "frames" => 12 }, "bad_order" => { "same_take" => "later", "frames" => 12 },
              "later" => { "image" => "a", "frames" => 24 } }
    shots = Pipeline::Steps::Shots.allocate
    allow(shots).to receive(:specs).and_return(specs)
    allow(shots).to receive(:project).and_return(double(path: "/out/04_shot_bite.mp4"))
    expect(shots.send(:generate, "again", specs["again"])).to eq(source: "bite", path: "/out/04_shot_bite.mp4")
    expect(shots.send(:source_skip, specs["again"])).to eq(29)
    expect { shots.send(:generate, "bad_still", specs["bad_still"]) }.to raise_error(ArgumentError, /not an earlier generated shot/)
    expect { shots.send(:generate, "bad_order", specs["bad_order"]) }.to raise_error(ArgumentError, /not an earlier generated shot/)
    expect(Pipeline::Believability.generated?(specs["again"])).to be(false)
  end

  it "asks Whisper for the language of each line, so Japanese is transcribed and not translated" do
    with_workspace do |dir|
      lines = File.join(dir, "lines.json")
      File.write(lines, JSON.generate([{ "name" => "ja", "character" => "a", "text" => "はい" }, { "name" => "en", "character" => "a", "text" => "yes" }]))
      data = { "lines" => lines, "tracks" => {}, "items" => { "ja" => { "url" => "u1" }, "en" => { "url" => "u2" } } }
      step = Pipeline::Steps::Dialogue.allocate
      allow(step).to receive_messages(key: :dialogue, client: nil, project: { dialogue: data }.tap { |h| h.define_singleton_method(:duration) { 1.0 } },
                                       specs: { "ja" => { "language_code" => "ja" }, "en" => {} })
      whisper = double
      allow(Fal::Models::Whisper).to receive(:new).and_return(whisper)
      allow(whisper).to receive(:transcribe).and_return(double(output: { "text" => "" }))
      step.send(:review)
      expect(whisper).to have_received(:transcribe).with(audio_url: "u1", language: "ja")
      expect(whisper).to have_received(:transcribe).with(audio_url: "u2", language: "en")
    end
  end
end

RSpec.describe "Believable motion rules", :core do
  rules = Pipeline::Believability

  def run_spec(prompt, camera) = { "prompt" => prompt, "camera" => { "move" => camera } }

  it "refuses action on green and accepts a performance that stays put" do
    fight = { "key" => "green", "prompt" => "He sprints forward and throws a punch." }
    talk = { "key" => "green", "prompt" => "He stands still and says his line. Nobody runs. No fighting." }
    expect(rules.clip_problems("a", fight).first).to include("sprints", "throws", "one H3 shot")
    expect(rules.clip_problems("b", talk)).to eq([])
  end

  it "does not treat a full-frame painted clip as a keyed one" do
    expect(rules.clip_problems("panel", { "key" => "none", "prompt" => "He punches the air." })).to eq([])
  end

  it "ignores action words that only appear in the style bible" do
    allow(Pipeline::Project).to receive(:style).and_return("A story about a fight.")
    expect(rules.clip_problems("a", { "key" => "green", "prompt" => "A story about a fight. He stands and talks." })).to eq([])
  end

  it "refuses a run without a travelling camera, and several runners in one shot" do
    locked = run_spec("He sprints along the river.", "locked-off")
    pair = run_spec("They sprint towards each other.", "fast lateral tracking shot")
    tracked = run_spec("He sprints along the river. The world rushes past.", "fast lateral tracking shot")
    expect(rules.shot_problems("locked", locked).join).to include("treadmill")
    expect(rules.shot_problems("pair", pair).join).to include("one runner per shot")
    expect(rules.shot_problems("tracked", tracked)).to eq([])
  end

  it "accepts a flagged word when the item explains itself" do
    hair = run_spec("He runs a hand through his hair.", "locked-off").merge("believable" => "no running, only a hand gesture")
    expect(rules.shot_problems("hair", hair)).to eq([])
  end

  it "stops a paid shot step before the first call" do
    step = Pipeline::Steps::Shots.allocate
    allow(step).to receive(:specs).and_return("bad" => run_spec("They sprint at each other.", "push-in"))
    expect { step.run! }.to raise_error(ArgumentError, /refused before any paid call/)
  end

  it "stops a paid clip step before the first call" do
    step = Pipeline::Steps::Clips.allocate
    allow(step).to receive(:specs).and_return("bad" => { "key" => "green", "prompt" => "He sprints." })
    expect { step.run! }.to raise_error(ArgumentError, /refused before any paid call/)
  end

  it "catches a colour split large enough to garble the picture" do
    expect(rules.cue_problems([{ "fx" => "rgb", "f" => 242, "amt" => 6 }]).join).to include("garbles")
    expect(rules.cue_problems([{ "fx" => "rgb", "f" => 242, "amt" => 0.006 }, { "fx" => "grain", "amt" => 3 }])).to eq([])
  end

  it "warns about pasted-on effects, sprites and full turns" do
    notes = rules.warnings(shots: { "s" => { "camera" => "a 360 orbit" } }, clips: { "c" => { "key" => "green" } }, overlay: "Anim.shockRing(x, y, p);")
    expect(notes.join).to include("keyed sprites (c)", "full camera turn", "shockRing")
  end
end

RSpec.describe "Near-ground motion measure", :media do
  # A textured ground under a fixed sky, with a block standing in for a runner whose limbs move while the ground stays.
  def clip(path, ground_speed)
    Open3.capture2e("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "nullsrc=s=960x540:r=24:d=2",
                    "-vf", "geq=lum='128+60*sin((X+#{ground_speed}*N)/9)*sin(Y/7)':cb=128:cr=128,format=yuv420p", path).last.success? or raise "ffmpeg failed"
    path
  end

  def world_speed(path)
    out, status = Open3.capture2(Media::Python.new.executable, File.join(SKILL, "scripts", "tools", "python", "world_motion.py"), path)
    raise out unless status.success?
    JSON.parse(out)["world_speed"]
  end

  it "reads a still ground as a treadmill and a passing ground as travel" do
    Dir.mktmpdir do |dir|
      expect(world_speed(clip(File.join(dir, "still.mp4"), 0))).to be < 0.05
      expect(world_speed(clip(File.join(dir, "moving.mp4"), 16))).to be > Pipeline::Believability::MIN_RUN_WORLD_SPEED
    end
  end
end
