require "rbconfig"
module Toolkit
  class TestRunner
    def run
      profile = ENV.fetch("PROFILE", "all")
      raise "PROFILE must be all, core, media, swift, live or seedance_live" unless %w[all core media swift live seedance_live].include?(profile)
      if profile == "live"
        raise "Paid tests require LIVE_FAL=1, LIVE_SONG=/path/to/song.wav and LIVE_LYRICS='recognizable words'" unless ENV["LIVE_FAL"] == "1" && File.file?(ENV["LIVE_SONG"].to_s) && !ENV["LIVE_LYRICS"].to_s.strip.empty?
      end
      if profile == "seedance_live"
        raise "Paid Seedance smoke requires LIVE_FAL=1 and LIVE_IMAGE=/path/to/reference.png" unless ENV["LIVE_FAL"] == "1" && File.file?(ENV["LIVE_IMAGE"].to_s)
      end
      # Specs chdir into temporary workspaces; pin the toolkit's own venv so Python helpers keep numpy/PIL.
      venv = File.expand_path(".venv/bin/python3")
      ENV["MV_PYTHON"] ||= venv if File.file?(venv)
      args = [RbConfig.ruby, "-S", "rspec", "spec", "--format", "documentation"]
      args += profile == "all" ? ["--tag", "~live"] : ["--tag", profile]
      args += ["--tag", "~seedance_live"] if profile == "live"
      ok = system(*args)
      raise "RSpec failed for PROFILE=#{profile}; see failures above" unless ok
    end
  end
end
