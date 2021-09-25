# -*- ruby -*-

clean_white_space = lambda do |entry|
  entry.gsub(/(\A\n+|\n+\z)/, '') + "\n"
end

require_relative "lib/apt-dists-merge/version"

Gem::Specification.new do |spec|
  spec.name = "apt-dists-merge"
  spec.version = APTDistsMerge::VERSION
  spec.homepage = "https://github.com/red-data-tools/apt-dists-merge"
  spec.authors = ["Sutou Kouhei"]
  spec.email = ["kou@clear-code.com"]

  readme = File.read("README.md")
  readme.force_encoding("UTF-8")
  entries = readme.split(/^\#\#\s(.*)$/)
  clean_white_space.call(entries[entries.index("Description") + 1])
  description = clean_white_space.call(entries[entries.index("Description") + 1])
  spec.summary, spec.description, = description.split(/\n\n+/, 3)
  spec.license = "MIT"
  spec.files = [
    "LICENSE.txt",
    "NEWS.md",
    "README.md",
  ]
  spec.files += Dir.glob("lib/**/*.rb")
  Dir.chdir("bin") do
    spec.executables = Dir.glob("*")
  end
end
