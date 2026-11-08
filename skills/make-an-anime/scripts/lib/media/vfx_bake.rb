require "digest"
require_relative "vfx"

module Media
  # A local finish between gen:overlay and sfx:mix. Keep the plain picture and
  # render to a temporary output so failures never replace the current overlay.
  class VfxBake < Shell
    def initialize(run, root: Vfx::ROOT)
      raise ArgumentError, "Invalid run" unless run.match?(/\A[a-zA-Z0-9_-]+\z/)
      @root, @name = root, run
    end

    def bake
      dir = File.join(@root, "output", @name)
      final, plain = %w[final_overlay.mp4 final_overlay_plain.mp4].map { File.join(dir, _1) }
      raise ArgumentError, "Run gen:overlay first: #{final}" unless File.file?(final)
      service = Vfx.new("#{@name}-vfx")
      raise ArgumentError, "Bake cues must read #{plain} and write #{final}" unless service.source == plain && service.out == final
      service.cues # validate before changing the backup
      stamp = service.path("baked.json")
      pending = "#{stamp}.pending"
      temp = File.join(dir, ".baking.mp4")
      File.open(service.path("bake.lock"), File::CREAT | File::RDWR) do |lock|
        lock.flock(File::LOCK_EX)
        digest = video_hash(final)
        previous = [pending, stamp].filter_map { |p| JSON.parse(File.read(p)) if File.file?(p) }
        baked = previous.find { |r| r["video_sha256"] == digest }
        if baked
          raise "Plain overlay missing or changed; rebuild gen:overlay before baking" unless File.file?(plain) && video_hash(plain) == baked["plain_sha256"]
          # Preserve a later dialogue remix without processing the baked picture twice.
          run("ffmpeg", "-v", "error", "-y", "-i", plain, "-i", final, "-map", "0:v:0", "-map", "1:a?", "-c", "copy", temp)
        else
          FileUtils.cp(final, temp)
        end
        File.rename(temp, plain)
        service.render(out_path: temp)
        receipt = { video_sha256: video_hash(temp), plain_sha256: video_hash(plain) }
        File.write(pending, JSON.pretty_generate(receipt))
        File.rename(temp, final)
        # A pending receipt also recognizes a completed output after a crash here.
        File.rename(pending, stamp)
        { path: final, plain: plain, reused_plain: !!baked }
      ensure
        FileUtils.rm_f(temp)
      end
    end

    private

    def video_hash(path)
      run("ffmpeg", "-v", "error", "-i", path, "-map", "0:v:0", "-c", "copy", "-f", "hash", "-hash", "sha256", "-", quiet: true).strip
    end
  end
end
