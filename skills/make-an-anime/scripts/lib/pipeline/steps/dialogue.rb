require "yaml"

module Pipeline
  module Steps
    # Step 3a — the scene's voiced lines (ElevenLabs Eleven v4 via Fal), placed on the scene timeline.
    #
    # config/cast.yml (shared by every scene) casts one voice per character:
    #   hero: { name: Hero, voice: Brian, stability: 0.45, similarity_boost: 0.8, ref: char-hero-v1 }
    # prompts/<run>/03_dialogue.yml lists the lines in any order:
    #   - name: kid-asks          # unique id, also the cache key (ONLY=kid-asks FORCE=1 regenerates one line)
    #     character: kid     # a cast.yml id
    #     at: 3.6                      # scene-local start time, seconds
    #     text: "[sleepy] Dad… are you making a game?"   # audio tags in [brackets] are performed, not spoken
    #     vo: false                    # true: narration/off-screen; mixed, but never drives a mouth
    #     subtitle: "Gatto! (Cat!)"    # optional: what the subtitle shows instead of `text` (a gloss); not sent to TTS
    #     gate_s: 0.28                 # optional: silence the start of the take in the mix (a blip before the first word)
    #     keep_s: 1.2                  # optional: keep only this much of the take (a long tail of breath or silence)
    #     inner: true                  # optional, with vo: a thought in the character's head, treated so it isn't heard as spoken
    #     subtitle: " "                # a blank subtitle: a laugh or breath with no caption, not counted as speech when levelling
    #     gain_db: -5                  # optional: level this take in the scene mix only (takes vary by ±8 dB); the mouth
    #                                  # track keeps the raw take, so H3 inputs and their cache are untouched
    # Line records also carry speech_at: `at` plus the take's measured leading silence, where the voice actually starts
    # (subtitles start there; the TTS alignment is not trusted for this — after a long tag it put a word 1.1 s late).
    #     # optional overrides: voice, stability, similarity_boost, seed, language_code
    #
    # Deliverables: 03_dialogue.wav (every line placed, scene length), 03_voice_<character>.wav (only that character's
    # on-screen lines, silent elsewhere: the H3 target audio for that character's shots, so the mouth rests while others
    # talk) and 03_dialogue_words.json (scene-local word cues [{w, s, e, character, line}] for subtitles and p5 timing).
    class Dialogue < ItemsStep
      MODEL = Fal::Models::ElevenTtsV4
      VOICE_KEYS = %w[stability similarity_boost seed language_code apply_text_normalization].freeze

      def self.cast(root = ROOT)
        path = File.join(root, "config", "cast.yml")
        raise "config/cast.yml is missing: cast one ElevenLabs voice per character first" unless File.file?(path)
        YAML.safe_load_file(path)
      end

      def cast = @cast ||= self.class.cast

      def specs
        @specs ||= yaml("03_dialogue").to_h do |line|
          name = line.fetch("name")
          raise ArgumentError, "line #{name}: unknown character #{line["character"].inspect} (cast: #{cast.keys.join(", ")})" unless cast.key?(line["character"])
          raise ArgumentError, "line #{name}: `at` must be a scene-local time in seconds" unless line["at"].is_a?(Numeric) && line["at"] >= 0
          [name, line]
        end
      end

      def generate(name, spec)
        voice = cast.fetch(spec.fetch("character"))
        opts = voice.slice(*VOICE_KEYS).merge(spec.slice(*VOICE_KEYS)).transform_keys(&:to_sym)
        result = MODEL.new(client: client).speak(text: spec.fetch("text"), voice: spec.fetch("voice", voice.fetch("voice")), **opts)
        url = result.output.fetch("audio").fetch("url")
        mp3 = download(url, "03_line_#{name}.mp3")
        wav = ffmpeg.extract_audio(mp3, project.path("03_line_#{name}.wav"))
        { request_id: result.request_id, input: result.input, url: url, path: wav, duration: ffmpeg.duration(wav).round(3),
          words: self.class.words(result.output["timestamps"]) }
      end

      def finish(items)
        length = project.duration
        lines = specs.map do |name, spec|
          item = items.fetch(name)
          { "name" => name, "character" => spec["character"], "text" => spec["text"], "at" => spec["at"].to_f,
            "end" => (spec["at"] + (spec["keep_s"] || item["duration"])).round(3), "vo" => !!spec["vo"], "path" => item["path"],
            "speech_at" => (spec["at"] + [ffmpeg.leading_silence(item["path"]), spec["gate_s"].to_f].max).round(3), "subtitle" => spec["subtitle"],
            "gate_s" => spec["gate_s"]&.to_f, "keep_s" => spec["keep_s"]&.to_f, "inner" => spec["inner"],
            "gain_db" => spec["gain_db"]&.to_f }.compact
        end.sort_by { |l| l["at"] }
        late = lines.select { |l| l["end"] > length + 0.05 }
        raise "lines end after the scene (#{length}s): #{late.map { |l| "#{l["name"]} ends #{l["end"]}s" }.join(", ")}; move `at` or lengthen the scene" if late.any?
        lines.group_by { |l| l["character"] }.each do |character, own|
          own.each_cons(2) do |a, b|
            raise "#{character} talks over themself: #{a["name"]} ends #{a["end"]}s, #{b["name"]} starts #{b["at"]}s" if b["at"] < a["end"]
          end
        end
        tracks = cast.keys.select { |c| lines.any? { |l| l["character"] == c } }.to_h do |character|
          own = lines.select { |l| l["character"] == character && !l["vo"] }.map { |l| l.except("gain_db") }
          [character, ffmpeg.place_audio(own, project.path("03_voice_#{character}.wav"), seconds: length)]
        end
        words = lines.flat_map do |l|
          self.class.spoken_words(items[l["name"]]["words"]).map { |w| w.merge("s" => (w["s"] + l["at"]).round(3), "e" => (w["e"] + l["at"]).round(3), "character" => l["character"], "line" => l["name"]) }
        end
        File.write(project.path("03_dialogue_words.json"), JSON.pretty_generate(words))
        File.write(project.path("03_dialogue_lines.json"), JSON.pretty_generate(lines.map { |l| l.except("path") }))
        { path: ffmpeg.place_audio(lines, project.path("03_dialogue.wav"), seconds: length), tracks: tracks,
          words: project.path("03_dialogue_words.json"), lines: project.path("03_dialogue_lines.json") }
      end

      # Local timing checks plus a paid Whisper pass per line, so a spoken audio tag or a dropped word is caught before animation.
      def review
        data = project[key]
        lines = JSON.parse(File.read(data["lines"]))
        whisper = Fal::Models::Whisper.new(client: client)
        heard = lines.to_h do |l|
          url = data.dig("items", l["name"], "url")
          # Whisper defaults to English and then translates another language instead of transcribing it.
          language = specs.dig(l["name"], "language_code") || "en"
          text = url ? whisper.transcribe(audio_url: url, language: language).output["text"].to_s.strip : ""
          [l["name"], text]
        end
        checks = lines.to_h do |l|
          want = self.class.spoken(l["text"])
          got = self.class.spoken(heard[l["name"]])
          missing, extra = self.class.word_diff(want, got)
          ["#{l["name"]} (#{l["character"]}) says its text", [missing.size <= [1, want.size / 6].max && extra.size <= [1, want.size / 6].max,
                                                             "heard #{heard[l["name"]].inspect}; missing #{missing.inspect}; extra #{extra.inspect}#{"; not Latin script, so compare it by reading" if want.empty?}"]]
        end
        tracks = data["tracks"].transform_values { |p| ffmpeg.summary(p)[:duration] }
        checks["mouth tracks are scene length"] = [tracks.values.all? { |d| (d - project.duration).abs < 0.05 }, tracks.inspect]
        { lines: lines, heard: heard, **verdict(checks) }
      end

      # Normalised spoken words of a line: audio tags in [brackets] and IPA in /slashes/ removed.
      # Words missing from / added to a take, counted as multisets: a doubled phrase ("Software should be free. Software
      # should be free — free as in freedom.") is extra words even though every word is also in the script.
      def self.word_diff(want, got)
        w, g = want.tally, got.tally
        [w.flat_map { |k, n| [k] * [n - g.fetch(k, 0), 0].max }, g.flat_map { |k, n| [k] * [n - w.fetch(k, 0), 0].max }]
      end

      def self.spoken(text)
        text.to_s.gsub(/\[[^\]]*\]/, " ").gsub(%r{/[^/]*/}, " ").downcase.unicode_normalize(:nfkd).gsub(/[^a-z0-9' ]/, " ").split
      end

      # ElevenLabs timestamps -> [{ "w", "s", "e" }] per word. Accepts word entries ({text|word, start, end}) or the
      # character alignment ({characters, character_start_times_seconds, character_end_times_seconds}).
      # Word cues without performed audio tags ("[sleepy," "mumbling]") or punctuation-only tokens ("…", "—").
      def self.spoken_words(words)
        depth = 0
        Array(words).filter_map do |w|
          text = w["w"].to_s
          inside = depth.positive? || text.start_with?("[")
          depth += text.count("[") - text.count("]")
          depth = 0 if depth.negative?
          rest = text.include?("]") ? text.sub(/\A.*\]/, "") : ""
          next if inside && rest.empty?
          text = rest if inside
          next unless text.match?(/[\p{L}\p{N}]/)
          w.merge("w" => text)
        end
      end

      def self.words(timestamps)
        return [] if timestamps.nil?
        entries = timestamps.is_a?(Hash) ? [timestamps] : Array(timestamps)
        if entries.first.is_a?(Hash) && entries.first.key?("characters")
          # Streamed alignments arrive in chunks that can split a word ("M" | "inecraft"): join them first.
          chars = entries.flat_map { |a| a["characters"].zip(a["character_start_times_seconds"], a["character_end_times_seconds"]) }
          chars.chunk_while { |x, y| x[0] !~ /\s/ && y[0] !~ /\s/ }.reject { |run| run.first[0] =~ /\s/ }
               .map { |run| { "w" => run.map(&:first).join, "s" => run.first[1].to_f, "e" => run.last[2].to_f } }
        else
          entries.filter_map do |t|
            next unless t.is_a?(Hash)
            word = t["text"] || t["word"] || t["w"]
            first = t["start"] || t["s"] || t.dig("timestamp", 0)
            last = t["end"] || t["e"] || t.dig("timestamp", 1)
            next if word.to_s.strip.empty? || first.nil? || last.nil?
            { "w" => word.to_s.strip, "s" => first.to_f, "e" => last.to_f }
          end
        end
      end

      protected

      def endpoint = MODEL.endpoint
    end
  end
end
