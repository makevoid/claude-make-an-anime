# Deterministic provider I/O for pipeline specs: every paid endpoint answers with a local fixture.
class SyntheticAnimeFal < Fal::Client
  attr_reader :calls, :uploads
  def initialize(image:, video:, voice:, music:)
    super(api_key: "fixture-only", poll_interval: 0)
    @files = { "fixture://image" => image, "fixture://video" => video, "fixture://voice" => voice, "fixture://music" => music }
    @calls, @uploads, @results = [], [], {}
  end
  def submit(endpoint, input)
    id = "fixture-#{@calls.size}"
    @calls << [endpoint, input]
    @results[id] = case endpoint
                   when /image-to-video/ then { "video" => { "url" => "fixture://video" } }
                   when /tts/ then { "audio" => { "url" => "fixture://voice" },
                                     "timestamps" => [{ "text" => "hello", "start" => 0.1, "end" => 0.5 }, { "text" => "there", "start" => 0.6, "end" => 1.0 }] }
                   when /music/ then { "audio" => { "url" => "fixture://music" } }
                   else { "images" => [{ "url" => "fixture://image" }] }
                   end
    { "request_id" => id, "status_url" => id, "response_url" => id }
  end
  def wait(*) = true
  def get_json(id) = @results.fetch(id)
  def upload(path, **)
    @uploads << path
    "fixture://upload/#{File.basename(path)}"
  end
  def download(url, path)
    FileUtils.cp(@files.fetch(url), path)
    path
  end
end
