require_relative "base"
require_relative "gpt_image26"

module Fal
  module Models
    # https://fal.ai/models/openai/gpt-image-2.6/sunburst/edit
    class GptImage26Edit < Base
      ENDPOINT = "openai/gpt-image-2.6/sunburst/edit".freeze
      DEFAULTS = GptImage26::DEFAULTS

      def edit(prompt:, image_urls:, aspect_ratio: "16:9", **opts)
        call(prompt: prompt, image_urls: image_urls, image_size: GptImage26::SIZES.fetch(aspect_ratio), **opts)
      end
    end
  end
end
