require_relative "seedance_image_to_video"

module Fal
  module Models
    class SeedanceReferenceToVideo < SeedanceImageToVideo
      ENDPOINT = "bytedance/seedance-2.5/us/reference-to-video".freeze
      PARAMS = %i[prompt image_urls video_urls audio_urls resolution draft duration aspect_ratio generate_audio bitrate_mode codec seed end_user_id task].freeze

      def animate(prompt:, duration:, image_urls: [], video_urls: [], audio_urls: [], **opts)
        call(prompt: prompt, duration: duration, image_urls: image_urls, video_urls: video_urls, audio_urls: audio_urls, **opts)
      end

      private

      def validate!(input)
        total = 0
        { image_urls: 30, video_urls: 10, audio_urls: 10 }.each do |key, limit|
          values = input.fetch(key, [])
          raise ArgumentError, "#{key} must be an array of up to #{limit} URLs" unless values.is_a?(Array) && values.size <= limit && values.all? { |v| v.is_a?(String) && !v.empty? }
          total += values.size
        end
        raise ArgumentError, "Seedance needs 1 to 50 reference files" unless (1..50).cover?(total)
        super
      end
    end
  end
end
