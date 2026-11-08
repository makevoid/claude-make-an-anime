require_relative "base"

module Fal
  module Models
    class SeedanceDraftComplete < Base
      ENDPOINT = "bytedance/seedance-2.5/us/draft/complete".freeze
      DEFAULTS = { resolution: "1080p", codec: "H264" }.freeze

      def complete(draft_id:, **opts) = call(draft_id: draft_id, **opts)

      private

      def validate!(input)
        raise ArgumentError, "draft_id is required" unless input[:draft_id].is_a?(String) && !input[:draft_id].strip.empty?
        raise ArgumentError, "Seedance draft completion only supports 1080p" unless input[:resolution] == "1080p"
        unknown = input.keys - %i[draft_id resolution codec]
        raise ArgumentError, "Unsupported draft completion params: #{unknown.join(', ')}" if unknown.any?
        super
      end
    end
  end
end
