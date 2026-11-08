require_relative "spec_helper"

RSpec.describe "Paid Seedance smoke", :live, :seedance_live do
  it "generates a real minimum-length 480p take and a three-second review clip" do
    raise "Set LIVE_FAL=1 and LIVE_IMAGE to a local reference image" unless ENV["LIVE_FAL"] == "1" && File.file?(ENV["LIVE_IMAGE"].to_s)
    reference = File.expand_path(ENV.fetch("LIVE_IMAGE"))
    dir = File.join(RT, "tmp", "seedance-live")
    FileUtils.mkdir_p(dir)
    Dir.chdir(dir) do
      FileUtils.mkdir_p("docs")
      File.write("docs/PLAN.md", "Seedance API smoke: upload the supplied reference; one 4-second image-to-video request at 480p without audio, then locally trim to 3 seconds. No paid retries, image generation, or draft completion.\n")
      Workflow::Approval.new.record!("User requested: make sure you test a short clip of 2-3s to make sure seedance works. API minimum is 4s; deliver a local 3s trim.")
      model = Fal::Models::SeedanceImageToVideo
      Fal::OpenAPI.fetch(model.endpoint)
      client = Fal::Client.new
      result = model.new(client: client).animate(
        prompt: "Animate this exact scene as one continuous anime shot. A gentle breeze moves loose fabric and hair, soft natural blinking and subtle breathing. Slow camera push in. Preserve the characters, setting and painted style. No cuts, no new objects, no text.",
        image_url: client.upload(reference), duration: 4)
      json("result.json", endpoint: model.endpoint, request_id: result.request_id, input: result.input, output: result.output)
      client.download(result.output.fetch("video").fetch("url"), "seedance-4s.mp4")
      summary = ff.summary("seedance-4s.mp4")
      expect(summary[:duration]).to be_between(3.9, 4.2)
      # Fal's 480p tier preserves source aspect ratio with rounded dimensions
      # (the live 16:9 fixture returns 856x478 rather than an exact 480 rows).
      expect(result.input[:resolution]).to eq("480p")
      expect([summary.dig(:video, :w), summary.dig(:video, :h)].min).to be_within(8).of(480)
      ff.run("ffmpeg", "-y", "-v", "error", "-i", "seedance-4s.mp4", "-t", "3", "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", "seedance-3s.mp4")
      sample = ff.summary("seedance-3s.mp4")
      expect(sample[:duration]).to be_within(0.05).of(3)
      ff.contact_sheet("seedance-3s.mp4", "contact-sheet.jpg", cols: 3, rows: 2)
      json("verification.json", source: summary, sample: sample, request_id: result.request_id)
      puts "Seedance artifacts: #{dir}"
    end
  end
end
