# Runs a bundled example from inside its initialised project with synthetic Fal media: the real prompts, config, steps and
# sketch, with no network. Usage: ruby spec/support/example_driver.rb (from the project root).
require "json"
require "fileutils"
require File.expand_path("lib/fal_mv_gen", Dir.pwd)
require File.expand_path("lib/toolkit/operations", Dir.pwd)
require_relative "synthetic_anime_fal"

fix = FileUtils.mkdir_p("tmp/fixtures").first
run = ->(*cmd) { system(*cmd, exception: true) }
image = "#{fix}/image.png"
run.("magick", "-size", "1920x1080", "xc:#00B140", "-fill", "#e02040", "-draw", "rectangle 760,200 1160,960", image)
voice = "#{fix}/voice.wav"
run.("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=300:duration=1.2", voice)
music = "#{fix}/music.wav"
run.("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=90:duration=12", music)
movie = "#{fix}/h3.mp4"
run.("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "color=#00B140:s=1366x768:r=24:d=5", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
     "-vf", "drawbox=x=500+40*t:y=100:w=300:h=560:color=#e02040:t=fill", "-t", "5", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", movie)

client = SyntheticAnimeFal.new(image: image, video: movie, voice: voice, music: music)
Workflow::Approval.new.record!("Synthetic example run; mocked network only")
Pipeline::GENERATIONS.each do |name, generation|
  project = Pipeline::Project.new(name)
  generation.fetch(:steps).each { |step| step.new(project: project, client: client).run! }
end
puts JSON.generate(calls: client.calls.map(&:first).tally, uploads: client.uploads.size)
