# Generate images and video from Ruby on SayMaker (https://saymaker.ai).
#
#   require "saymaker"
#   url  = SayMaker.generate("a paper-cut layered mountain range at dusk")
#   clip = SayMaker.generate_video("a fox trotting through snow", duration: 6)
#
# One API key runs the whole shelf on your own credits: Veo 3.1, Kling 3.0,
# Seedance 2.0, MiniMax H3, Nano Banana 2, GPT Image 2.5, Seedream 5.0 and more.
# Create a key at https://saymaker.ai/settings/apikeys and set SAYMAKER_API_KEY
# or pass api_key:. Standard library only.
require "json"
require "net/http"
require "uri"
require_relative "saymaker/version"

module SayMaker
  BASE = "https://saymaker.ai"
  KEYS_URL = "#{BASE}/settings/apikeys"
  MODEL_IMAGE = "saymaker-image-v1"
  MODEL_EDIT = "nano-banana-2-lite"
  # The video model a free account can run (480p or 768p, 4 to 15 seconds).
  MODEL_VIDEO = "minimax-h3-fast"

  # Model id => the routing field the API expects next to it. Unlisted ids go as "kie".
  MODELS = {
    "saymaker-image-v1" => "kie", "nano-banana-2-lite" => "kie", "nano-banana-2" => "poyo",
    "nano-banana-pro" => "poyo", "gpt-image-2" => "poyo", "gpt-image-2-5-flare" => "kie",
    "seedream-5-lite" => "poyo", "seedream-5-pro" => "kie", "qwen-image-3-pro" => "kie",
    "grok-imagine-image-2-0" => "poyo", "minimax-h3-fast" => "vgenv", "minimax-h3" => "poyo",
    "seedance-2" => "kie", "seedance-2-fast" => "kie", "seedance-2-5" => "kie", "veo-3-1" => "kie",
    "kling-3-0" => "kie", "kling-3-0-turbo" => "kie", "wan-3-0" => "kie", "ltx-2-5-fast" => "replicate"
  }.freeze

  class Error < StandardError; end
  # No API key, or the key is invalid or deleted.
  class AuthError < Error; end
  # The account is out of credits.
  class QuotaError < Error; end
  # The model needs a paid plan or a credit pack.
  class PlanError < Error; end
  # Another run on this account is still rendering. Free accounts run one at a time.
  class BusyError < Error; end
  # The content filter or the model refused the prompt. Reword it.
  class RejectedError < Error; end

  module_function

  # Generate one image, or edit +image_url+, and return its URL.
  def generate(prompt, image_url: nil, model: nil, aspect_ratio: nil, api_key: nil,
               timeout: 4500, poll_every: 5, base_url: BASE, transport: nil)
    check_url(image_url)
    options = { "size" => aspect_ratio || (image_url ? "auto" : "1:1"), "resolution" => "1K", "n" => 1 }
    options["image_input"] = [image_url] if image_url
    run("image", image_url ? "image-to-image" : "text-to-image",
        model || (image_url ? MODEL_EDIT : MODEL_IMAGE), prompt, options,
        api_key, timeout, poll_every, base_url, transport)
  end

  # Generate one clip, or animate +image_url+ as the first frame, and return its URL.
  def generate_video(prompt, image_url: nil, model: MODEL_VIDEO, duration: nil, resolution: nil,
                     aspect_ratio: "16:9", sound: true, api_key: nil, timeout: 5400,
                     poll_every: 10, base_url: BASE, transport: nil)
    check_url(image_url)
    options = { "aspect_ratio" => aspect_ratio, "sound" => sound }
    options["image_input"] = [image_url] if image_url
    options["duration"] = duration if duration
    options["resolution"] = resolution if resolution
    run("video", image_url ? "image-to-video" : "text-to-video", model, prompt, options,
        api_key, timeout, poll_every, base_url, transport)
  end

  def check_url(url)
    return if url.nil? || url.start_with?("http://", "https://")

    raise ArgumentError, "image_url must be a public http(s) url"
  end

  def http(url, body, key)
    uri = URI(url)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{key}"
    req["User-Agent"] = "saymaker-ruby/#{VERSION}"
    req.body = JSON.generate(body)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 60) { |h| h.request(req) }
    JSON.parse(res.body.to_s.empty? ? "{}" : res.body)
  end

  # Refusals answer HTTP 200 with code -1; the status code alone reads as success.
  def classify(env)
    msg = (env["message"] || "request refused").to_s
    low = msg.downcase
    return BusyError.new(msg) if (env["data"].is_a?(Hash) && env["data"]["busy"]) || low.include?("is rendering") || low.include?("at once")
    return AuthError.new(msg) if low.include?("api key") || low.include?("no auth")
    return QuotaError.new(msg) if low.include?("insufficient credits")
    return PlanError.new(msg) if low.include?("subscription") || low.include?("plan") || low.include?("sign in")

    Error.new(msg)
  end

  def run(media, scene, model, prompt, options, api_key, timeout, poll_every, base_url, transport)
    raise ArgumentError, "prompt is required" if prompt.to_s.strip.empty?

    key = api_key || ENV["SAYMAKER_API_KEY"]
    raise AuthError, "pass api_key: or set SAYMAKER_API_KEY; create a key at #{KEYS_URL}" if key.nil? || key.empty?

    send = transport || method(:http)
    env = send.call("#{base_url}/api/ai/generate", {
      "provider" => MODELS.fetch(model, "kie"), "mediaType" => media, "model" => model,
      "scene" => scene, "prompt" => prompt, "options" => options
    }, key)
    raise classify(env) unless env["code"] == 0

    data = env["data"] || {}
    # A signed-out request is also a 200 with code 0 — only `wall` tells it apart.
    raise AuthError, "SayMaker needs an API key; create one at #{KEYS_URL}" if data["wall"]

    task = data["id"] or raise Error, "the service returned no task id"
    # Free-account runs only reach the model on the poll that crosses the end of
    # the queue wait, so polling is what starts the work.
    deadline = Time.now + timeout
    while Time.now < deadline
      sleep poll_every
      begin
        q = send.call("#{base_url}/api/ai/query", { "taskId" => task }, key)
      rescue StandardError
        next # a dropped poll is not a failed generation
      end
      next unless q["code"] == 0

      d = q["data"] || {}
      %w[cleanImages images videos].each { |f| return d[f][0] if d[f].is_a?(Array) && !d[f].empty? }
      raise RejectedError, "the run failed; reword the prompt rather than retrying" if %w[failed error].include?(d["status"].to_s.downcase)
    end
    raise Error, "deadline passed after #{timeout}s; the run may still finish in your SayMaker history"
  end
end
