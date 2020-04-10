
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "ipcam/version"

Gem::Specification.new do |spec|
  spec.name          = "ipcam"
  spec.version       = IPCam::VERSION
  spec.authors       = ["Hirosho Kuwagata"]
  spec.email         = ["kgt9221@gmail.com"]

  spec.summary       = %q{Sample application for "V4L2 for Ruby".}
  spec.description   = %q{Sample application for "V4L2 for Ruby".}
  spec.homepage      = "https://github.com/kwgt/ipcam"
  spec.license       = "MIT"

  if spec.respond_to?(:metadata)
    spec.metadata["homepage_uri"] = spec.homepage
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been
  # added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f|
      f.match(%r{^(test|spec|features|run\.sh)/})
    }
  end

  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["none"]

  spec.required_ruby_version = ">= 2.4.0"

  spec.add_development_dependency "bundler", ">= 2.1"
  spec.add_development_dependency "rake", ">= 12.3.3"
  spec.add_dependency "v4l2-ruby", "~> 0.10.0"
  spec.add_dependency "puma", "~> 4.3.3"
  spec.add_dependency "sinatra", "~> 2.0.5"
  spec.add_dependency "sinatra-contrib", "~> 2.0.5"
  spec.add_dependency "sassc", "~> 2.0.1"
  spec.add_dependency "eventmachine", "~> 1.2.7"
  spec.add_dependency "em-websocket", "~> 0.5.1"
  spec.add_dependency "msgpack", "~> 1.2.6"
  spec.add_dependency "msgpack-rpc-stack", "~> 0.7.1"
end
