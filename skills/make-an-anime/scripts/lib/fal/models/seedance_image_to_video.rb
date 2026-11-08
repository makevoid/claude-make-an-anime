require_relative "base"

module Fal
  module Models
    class SeedanceImageToVideo < Base
      ENDPOINT = "bytedance/seedance-2.5/us/image-to-video".freeze
      DEFAULT_RES = "480p".freeze
      DEFAULTS = { resolution: DEFAULT_RES, generate_audio: false, codec: "H264" }.freeze
      PARAMS = %i[prompt image_url end_image_url resolution draft duration aspect_ratio generate_audio bitrate_mode codec end_user_id].freeze

      # Seedance takes whole seconds, encoded as strings. The timeline can trim
      # the four-second minimum down to a shorter shot without retiming it.
      def self.duration(seconds)
        return "auto" if seconds == "auto"
        value = Float(seconds)
        raise ArgumentError, "Seedance duration must be positive and at most 30 seconds" unless value.finite? && value > 0 && value <= 30
        [4, value.ceil].max.to_s
      end

      def animate(prompt:, image_url:, duration:, **opts)
        call(prompt: prompt, image_url: image_url, duration: duration, **opts)
      end

      def call(**input)
        input[:duration] = self.class.duration(input[:duration]) if input.key?(:duration)
        input[:resolution] = input[:resolution].downcase if input[:resolution].is_a?(String)
        super(**input)
      end

      private

      # Keep basic validation active even before openapi:fetch has been run.
      def validate!(input)
        unknown = input.keys - self.class::PARAMS
        raise ArgumentError, "#{self.class.endpoint}: unsupported params #{unknown.join(', ')}" if unknown.any?
        raise ArgumentError, "Seedance resolution must be 480p, 720p or 1080p" unless %w[480p 720p 1080p].include?(input[:resolution])
        %i[draft generate_audio].each do |key|
          raise ArgumentError, "#{key} must be true or false" if input.key?(key) && ![true, false].include?(input[key])
        end
        raise ArgumentError, "Seedance drafts require resolution: 480p" if input[:draft] && input[:resolution] != "480p"
        if self.class == SeedanceImageToVideo
          raise ArgumentError, "Seedance image-to-video needs image_url" if input[:image_url].to_s.empty?
          raise ArgumentError, "Seedance image-to-video aspect_ratio must be auto" if input[:aspect_ratio] && input[:aspect_ratio] != "auto"
        end
        super
      end
    end
  end
end
