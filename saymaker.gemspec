require_relative "lib/saymaker/version"

Gem::Specification.new do |s|
  s.name        = "saymaker"
  s.version     = SayMaker::VERSION
  s.summary     = "Generate images and video from Ruby on SayMaker: Veo 3.1, Kling 3.0, Seedance 2.0, Nano Banana 2 with one API key"
  s.description = "A zero-dependency client for saymaker.ai: text-to-image, photo edits and text- or image-to-video across Veo 3.1, Kling 3.0, Seedance 2.0, MiniMax H3, Nano Banana 2, GPT Image 2.5 and Seedream 5.0, on one API key."
  s.authors     = ["SayMaker"]
  s.homepage    = "https://saymaker.ai/?utm_source=rubygems&utm_medium=package"
  s.license     = "MIT"
  s.files       = Dir["lib/**/*.rb"] + ["README.md", "LICENSE"]
  s.required_ruby_version = ">= 2.6"
  s.metadata    = {
    "homepage_uri"      => "https://saymaker.ai/?utm_source=rubygems&utm_medium=package",
    "source_code_uri"   => "https://github.com/hanshs474/saymaker-rb",
    "documentation_uri" => "https://saymaker.ai/video?utm_source=rubygems&utm_medium=package",
    "bug_tracker_uri"   => "https://github.com/hanshs474/saymaker-rb/issues",
    "rubygems_mfa_required" => "false"
  }
end
