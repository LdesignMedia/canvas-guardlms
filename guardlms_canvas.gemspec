# frozen_string_literal: true
Gem::Specification.new do |spec|
  spec.name = "guardlms_canvas"
  spec.version = "0.1.0"
  spec.authors = ["Ldesign Media"]
  spec.summary = "Site-bound Canvas inventory reporting for GuardLMS"
  spec.homepage = "https://guardlms.com"
  spec.license = "MIT"
  spec.metadata = {
    "source_code_uri" => "https://github.com/LdesignMedia/canvas-guardlms",
    "bug_tracker_uri" => "https://github.com/LdesignMedia/canvas-guardlms/issues"
  }
  spec.required_ruby_version = ">= 3.1"
  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
