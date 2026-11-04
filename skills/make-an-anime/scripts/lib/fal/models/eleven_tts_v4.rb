require_relative "base"

module Fal
  module Models
    # https://fal.ai/models/elevenlabs/tts/eleven-v4 — one character's line of dialogue or narration.
    # `voice` is an ElevenLabs voice name (Aria, Roger, Sarah, Laura, Charlie, George, Callum, River, Liam, Charlotte, Alice,
    # Matilda, Will, Jessica, Eric, Chris, Brian, Daniel, Lily, Bill, …) or voice ID. The text accepts audio tags such as
    # [whispering], [sleepy], [softly] and IPA in /slashes/. timestamps: true returns per-word timings for lip-sync and cues.
    class ElevenTtsV4 < Base
      ENDPOINT = "elevenlabs/tts/eleven-v4".freeze
      DEFAULTS = { output_format: "mp3_44100_192", timestamps: true, stability: 0.5, similarity_boost: 0.75 }.freeze

      def speak(text:, voice:, **opts)
        call(text: text, voice: voice, **opts)
      end
    end
  end
end
