require_relative "base"

module Fal
  module Models
    # https://fal.ai/models/openai/gpt-image-2.6/sunburst/text-to-image
    # 2.6 has no xhigh quality: quality stops at high. Its schema also lists reasoning_effort xhigh and max, but on 2026-11-05
    # the API refused both with a 422 ("not supported for this image model"), so reasoning_effort stays at high.
    class GptImage26 < Base
      ENDPOINT = "openai/gpt-image-2.6/sunburst/text-to-image".freeze
      DEFAULTS = { quality: "high", reasoning_effort: "high", output_format: "png", num_images: 1 }.freeze
      # Explicit sizes (multiples of 16) matching nano-banana-2's 2K output, so generations compare 1:1.
      SIZES = { "16:9" => { width: 2752, height: 1536 } }.freeze

      # Same signature as NanoBanana2#generate; this endpoint has no seed param.
      def generate(prompt:, aspect_ratio: "16:9", seed: nil, **opts)
        call(prompt: prompt, image_size: SIZES.fetch(aspect_ratio), **opts)
      end
    end
  end
end
