require "minitest/autorun"
require_relative "../lib/saymaker"

class SayMakerTest < Minitest::Test
  def fake(calls, final)
    lambda do |url, body, key|
      calls << [url, body, key]
      url.end_with?("/api/ai/generate") ? { "code" => 0, "data" => { "id" => "row1" } } : { "code" => 0, "data" => final }
    end
  end

  def test_image_prefers_clean
    calls = []
    url = SayMaker.generate("x", api_key: "sk", poll_every: 0, transport: fake(calls, { "images" => ["m"], "cleanImages" => ["c"] }))
    assert_equal "c", url
    assert_equal "saymaker-image-v1", calls[0][1]["model"]
    assert_equal({ "taskId" => "row1" }, calls[1][1])
  end

  def test_video_routes
    calls = []
    url = SayMaker.generate_video("x", api_key: "sk", duration: 6, poll_every: 0, transport: fake(calls, { "videos" => ["v"] }))
    assert_equal "v", url
    assert_equal "vgenv", calls[0][1]["provider"]
    assert_equal 6, calls[0][1]["options"]["duration"]
  end

  def test_errors
    ENV.delete("SAYMAKER_API_KEY")
    assert_raises(SayMaker::AuthError) { SayMaker.generate("x") }
    assert_kind_of SayMaker::QuotaError, SayMaker.classify({ "message" => "insufficient credits" })
    assert_kind_of SayMaker::BusyError, SayMaker.classify({ "message" => "Your current run is rendering. Plans on the pricing page" })
  end
end
