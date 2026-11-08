require_relative "base"

module Fal
  module Models
    # https://fal.ai/models/elevenlabs/sound-effects/v3/api
    class ElevenlabsSfx < Base
      ENDPOINT = "elevenlabs/sound-effects/v3".freeze

      def generate(prompt:, duration: 2, prompt_influence: 0.3, loop: false)
        raise ArgumentError, "SFX prompt must contain 1–450 characters" unless prompt.is_a?(String) && !prompt.strip.empty? && prompt.length <= 450
        raise ArgumentError, "SFX duration must be 0.5–30 seconds" unless duration.is_a?(Numeric) && (0.5..30).cover?(duration)
        raise ArgumentError, "SFX prompt_influence must be 0–1" unless prompt_influence.is_a?(Numeric) && (0..1).cover?(prompt_influence)
        raise ArgumentError, "SFX loop must be true or false" unless [true, false].include?(loop)

        call(text: prompt, duration_seconds: duration, prompt_influence: prompt_influence,
             loop: loop, output_format: "mp3_44100_128")
      end
    end
  end
end
