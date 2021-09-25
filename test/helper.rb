require "fileutils"
require "stringio"
require "tempfile"
require "tmpdir"
require "zlib"

require_relative "../lib/apt-dists-merge"

module Helper
  def fixture_path(*components)
    File.join(__dir__, "fixture", *components)
  end
end
