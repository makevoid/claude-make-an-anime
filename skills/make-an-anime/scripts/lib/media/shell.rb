require "open3"
require "fileutils"
require "shellwords"

module Media
  class CommandError < StandardError; end

  MIME_TYPES = {
    ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".webp" => "image/webp",
    ".mp3" => "audio/mpeg", ".wav" => "audio/wav", ".m4a" => "audio/mp4",
    ".mp4" => "video/mp4", ".mov" => "video/quicktime", ".webm" => "video/webm"
  }.freeze

  # Explicit font file for magick labels / ffmpeg drawtext (no fontconfig default on macOS brew builds).
  FONT = [ENV["MEDIA_FONT"], "/System/Library/Fonts/Supplemental/Arial.ttf", "/Library/Fonts/Arial Unicode.ttf",
          File.join(ENV.fetch("WINDIR", "C:/Windows"), "Fonts", "arial.ttf"), "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
           .compact.find { |f| File.exist?(f) }

  # Chrome (or Chromium-based Edge) for headless p5 rendering; keep in step with tools/p5/render.mjs.
  def self.chrome_paths
    dirs = [ENV["ProgramFiles"], ENV["ProgramFiles(x86)"], ENV["LOCALAPPDATA"]].compact
    [ENV["CHROME_PATH"], "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/usr/bin/google-chrome", "/usr/bin/chromium",
     *dirs.map { |d| File.join(d, "Google", "Chrome", "Application", "chrome.exe") },
     *dirs.map { |d| File.join(d, "Microsoft", "Edge", "Application", "msedge.exe") }].compact
  end

  def self.mime_type(path)
    MIME_TYPES.fetch(File.extname(path).downcase, "application/octet-stream")
  end

  # Base for wrappers around local CLI tools (ffmpeg, magick, python3).
  class Shell
    # Executable on PATH, found without a shell (`command -v` does not exist in Windows' cmd.exe).
    def self.available?(bin)
      exts = Gem.win_platform? ? ["", *ENV.fetch("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";")] : [""]
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        exts.any? { |ext| (f = File.join(dir, "#{bin}#{ext}")) && File.file?(f) && File.executable?(f) }
      end
    end

    def run(*cmd, quiet: false)
      warn "  $ #{cmd.shelljoin}" unless quiet
      out, err, status = Open3.capture3(*cmd.map(&:to_s))
      raise CommandError, "#{cmd.first} failed (#{status.exitstatus}):\n#{err[-2000..] || err}" unless status.success?
      out
    end
  end
end
