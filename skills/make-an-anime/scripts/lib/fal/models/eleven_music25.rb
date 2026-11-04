require_relative "base"

module Fal
  module Models
    # https://fal.ai/models/elevenlabs/music/v2.5 — the episode score. Either a plain `prompt` (+ music_length_ms,
    # force_instrumental) or a `composition_plan: { chunks: [{ text, duration_ms, positive_styles, negative_styles,
    # context_adherence }] }` whose chunks follow the storyboard's beats (3–120 s each, at most 30).
    class ElevenMusic25 < Base
      ENDPOINT = "elevenlabs/music/v2.5".freeze
      DEFAULTS = { output_format: "mp3_48000_192" }.freeze

      # Same keyword shape as Music3#compose, so the Music step can call either model.
      def compose(prompt: nil, composition_plan: nil, duration: nil, lyrics: nil, seed: nil, **opts)
        if composition_plan
          call(composition_plan: composition_plan, seed: seed, **opts)
        else
          call(prompt: prompt, music_length_ms: duration && (duration * 1000).round, force_instrumental: lyrics.to_s.strip.empty?, **opts)
        end
      end
    end
  end
end
