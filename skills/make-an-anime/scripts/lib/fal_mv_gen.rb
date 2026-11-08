$LOAD_PATH.unshift(__dir__)
require "uri"
Dir[File.join(__dir__, "media", "*.rb")].sort.each { |f| require f }
require "fal/client"
require "fal/openapi"
Dir[File.join(__dir__, "fal", "models", "*.rb")].sort.each { |f| require f }
require "pipeline/believability"
require "pipeline/project"
require "pipeline/step"
require "pipeline/items_step"
require "pipeline/generation_config"
require "pipeline/video_generation"
Dir[File.join(__dir__, "pipeline", "steps", "*.rb")].sort.each { |f| require f }
module Pipeline
  DEFAULT_RUN = "s01"
  ALL_STEPS = [Steps::RefBase, Steps::RefTorn, Steps::Dialogue, Steps::Music, Steps::Mix, Steps::Keyframes,
               Steps::Video, Steps::Shots, Steps::Clips, Steps::Overlay].freeze
  def self.section(at, frames)
    raise ArgumentError, "at and frames must be integer frame counts" unless at.is_a?(Integer) && at >= 0 && frames.is_a?(Integer) && frames > 0
    { music_from: "audio/song.wav", music_offset: at / 24.0, frames: frames, lyrics: [] }
  end

  # An anime scene: its own dialogue, score and soundtrack, `frames` long at 24fps (scenes are joined in order with media:concat).
  def self.scene(frames, **opts)
    raise ArgumentError, "frames must be a positive integer frame count" unless frames.is_a?(Integer) && frames > 0
    { frames: frames, upload_music: false, **opts }
  end
  GENERATIONS = GenerationConfig.new(ROOT).load.freeze
end
