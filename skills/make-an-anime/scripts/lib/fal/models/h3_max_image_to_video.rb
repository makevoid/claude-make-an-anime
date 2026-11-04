require_relative "base"

module Fal
  module Models
    # https://fal.ai/models/minimax/h3-max/image-to-video
    # Anime default: 768P native (H3 has no 720P tier; 480P/768P/1080P), the edit is upscaled to the 1080p delivery.
    # VIDEO_RES=1080P selects H3's latent refinement for a hero shot.
    class H3MaxImageToVideo < Base
      ENDPOINT = "minimax/h3-max/image-to-video".freeze
      DEFAULT_RES = "768P".freeze
      DEFAULTS = { resolution: DEFAULT_RES, prompt_expansion_mode: "disabled", enable_safety_checker: true }.freeze

      def animate(prompt:, image_url:, duration:, target_audio_url: nil, **opts)
        call(prompt: prompt, image_url: image_url, duration: duration, target_audio_url: target_audio_url, **opts)
      end
    end
  end
end
