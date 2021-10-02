require "fileutils"

module APTDistsMerge
  class Merger
    def initialize(base_dir, incoming_dir, merged_dir)
      @base_dir = base_dir
      @incoming_dir = incoming_dir
      @merged_dir = merged_dir
    end

    def merge
      unless File.exist?(@base_dir)
        FileUtils.rm_rf(@merged_dir)
        FileUtils.mkdir_p(@merged_dir)
        FileUtils.cp_r(Dir.glob("#{@incoming_dir}/*"), @merged_dir)
        return true
      end

      components = (detect_components(@base_dir) |
                    detect_components(@incoming_dir))
      components.each do |component|
        return false unless merge_component(component)
      end
      return false unless merge_release
      true
    end

    private
    def detect_extensions(base_path)
      Dir.glob("#{base_path}*").collect do |path|
        path.gsub(/\A#{Regexp.escape(base_path)}/, "")
      end
    end

    def read_data(path)
      if File.exist?(path)
        File.read(path)
      elsif File.exist?("#{path}.gz")
        real_path = "#{path}.gz"
        Zlib::GzipReader.open(real_path) do |input|
          input.read
        end
      elsif File.exist?("#{path}.xz")
        real_path = "#{path}.xz"
        IO.popen(["xz", "--decompress", "--stdout", real_path]) do |input|
          input.read
        end
      else
        nil
      end
    end

    def write_data(data, path, extensions=nil)
      FileUtils.mkdir_p(File.dirname(path))
      extensions ||= [""]
      extensions.each do |extension|
        case extension
        when ".gz"
          Zlib::GzipWriter.open("#{path}#{extension}") do |output|
            output.write(data)
          end
        when ".xz"
          IO.popen(["xz", "--stdout"], "r+") do |xz|
            writer = Thread.new do
              xz.write(data)
              xz.close_write
            end
            File.open("#{path}#{extension}", "wb") do |output|
              reader = Thread.new do
                IO.copy_stream(xz, output)
              end
              writer.join
              reader.join
            end
          end
        else
          File.open(path, "w") do |output|
            output.write(data)
          end
        end
      end
    end

    def release_path(dir)
      "#{dir}/Release"
    end

    def source_release_path(dir, component)
      "#{dir}/#{component}/source/Release"
    end

    def sources_path(dir, component)
      "#{dir}/#{component}/source/Sources"
    end

    def contents_path(dir, component, arch)
      "#{dir}/#{component}/Contents-#{arch}"
    end

    def packages_path(dir, component, arch)
      "#{dir}/#{component}/binary-#{arch}/Packages"
    end

    def binary_release_path(dir, component, arch)
      "#{dir}/#{component}/binary-#{arch}/Release"
    end

    def detect_architectures(dir)
      data = read_data(release_path(dir))
      return [] if data.nil?
      data.each_line do |line|
        case line
        when /\AArchitectures:\s*/
          return Regexp.last_match.post_match.split(/\s+/)
        end
      end
      []
    end

    def detect_components(dir)
      components = []
      Dir.open(dir) do |d|
        d.each do |path|
          full_path = "#{dir}/#{path}"
          next if path.start_with?(".")
          next unless File.directory?(full_path)
          components << path
        end
      end
      components
    end

    def merge_component(component)
      architectures = (detect_architectures(@base_dir) |
                       detect_architectures(@incoming_dir))
      architectures.each do |arch|
        return false unless merge_architecture(component, arch)
      end
      if File.exist?(source_release_path(@base_dir, component)) or
        File.exist?(source_release_path(@incoming_dir, component))
        return false unless merge_source(component)
      end
      true
    end

    def merge_architecture(component, arch)
      return false unless merge_contents(component, arch)
      return false unless merge_packages(component, arch)
      return false unless merge_binary_release(component, arch)
      true
    end

    def merge_contents(component, arch)
      base_path = contents_path(@base_dir, component, arch)
      incoming_path = contents_path(@incoming_dir, component, arch)
      base = read_data(base_path)
      incoming = read_data(incoming_path)
      merged = (base.lines | incoming.lines).sort
      merged_path = contents_path(@merged_dir, component, arch)
      write_data(merged.join,
                 merged_path,
                 detect_extensions(base_path) |
                 detect_extensions(incoming_path))
      true
    end

    def parse_deb822(content)
      data = {}
      key = nil
      content.each_line do |line|
        case line
        when /\A /
          data[key] << "\n" << line
        else
          key, value = line.split(/:\s*/, 2)
          data[key] = value.chomp
        end
      end
      data
    end

    def read_packages(path)
      read_data(path).split("\n\n").collect do |content|
        [parse_deb822(content), content]
      end
    end

    def debian_version_compare(a, b)
      if system("dpkg", "--compare-versions", a, "eq", b)
        0
      elsif system("dpkg", "--compare-versions", a, "lt", b)
        -1
      else
        1
      end
    end

    def merge_packages_data(base, incoming)
      packages = (base + incoming).uniq do |metadata,|
        [metadata["Package"], metadata["Version"]]
      end
      packages.sort do |a, b|
        a_metadata = a[0]
        b_metadata = b[0]
        a_package = a_metadata["Package"]
        b_package = b_metadata["Package"]
        package_compare = (a_package <=> b_package)
        if package_compare == 0
          debian_version_compare(a_metadata["Version"], b_metadata["Version"])
        else
          if a_package.start_with?(b_package)
            -1
          else
            package_compare
          end
        end
      end
    end

    def merge_packages(component, arch)
      base_path = packages_path(@base_dir, component, arch)
      incoming_path = packages_path(@incoming_dir, component, arch)
      base = read_packages(base_path)
      incoming = read_packages(incoming_path)
      merged = merge_packages_data(base, incoming)
      merged_path = packages_path(@merged_dir, component, arch)
      write_data(merged.collect {|_, content| "#{content}\n\n"}.join,
                 merged_path,
                 detect_extensions(base_path) |
                 detect_extensions(incoming_path))
      true
    end

    def merge_binary_release(component, arch)
      base_path = binary_release_path(@base_dir, component, arch)
      incoming_path = binary_release_path(@incoming_dir, component, arch)
      base = read_data(base_path)
      incoming = read_data(incoming_path)
      merged = incoming || base
      merged_path = binary_release_path(@merged_dir, component, arch)
      write_data(merged,
                 merged_path,
                 detect_extensions(base_path) |
                 detect_extensions(incoming_path))
      true
    end

    def merge_source(component)
      return false unless merge_sources(component)
      return false unless merge_source_release(component)
      true
    end

    def merge_sources(component)
      base_path = sources_path(@base_dir, component)
      incoming_path = sources_path(@incoming_dir, component)
      base = read_packages(base_path)
      incoming = read_packages(incoming_path)
      merged = merge_packages_data(base, incoming)
      merged_path = sources_path(@merged_dir, component)
      write_data(merged.collect {|_, content| "#{content}\n\n"}.join,
                 merged_path,
                 detect_extensions(base_path) |
                 detect_extensions(incoming_path))
      true
    end

    def merge_source_release(component)
      base_path = source_release_path(@base_dir, component)
      incoming_path = source_release_path(@incoming_dir, component)
      base = read_data(base_path)
      incoming = read_data(incoming_path)
      merged = incoming || base
      merged_path = source_release_path(@merged_dir, component)
      write_data(merged,
                 merged_path,
                 detect_extensions(base_path) |
                 detect_extensions(incoming_path))
      true
    end

    def read_release(path)
      parse_deb822(read_data(path))
    end

    def generate_checksums(dir, files, digest_class)
      checksums = files.collect do |file|
        checksum = digest_class.file(file).to_s
        size = File.size(file)
        relative_path = file.gsub(/\A#{Regexp.escape(dir)}\//, "")
        " %s %16d %s" % [checksum, size, relative_path]
      end
      checksums.join("\n")
    end

    def merge_release
      base = read_release(release_path(@base_dir))
      incoming = read_release(release_path(@incoming_dir))
      architectures = base["Architectures"].split |
                      incoming["Architectures"].split
      components = base["Components"].split |
                   incoming["Components"].split
      files = Dir.glob("#{@merged_dir}/**/*")
      files = files.reject do |file|
        File.directory?(file)
      end
      files = files.sort
      merged = <<-RELEASE
Architectures: #{architectures.sort.join(" ")}
Codename: #{incoming["Codename"]}
Components: #{components.sort.join(" ")}
Date: #{incoming["Date"]}
Description: #{incoming["Description"]}
Label: #{incoming["Label"]}
Origin: #{incoming["Origin"]}
Suite: #{incoming["Suite"]}
MD5Sum:
#{generate_checksums(@merged_dir, files, Digest::MD5)}
SHA1:
#{generate_checksums(@merged_dir, files, Digest::SHA1)}
SHA256:
#{generate_checksums(@merged_dir, files, Digest::SHA256)}
SHA512:
#{generate_checksums(@merged_dir, files, Digest::SHA512)}
      RELEASE
      merged_path = release_path(@merged_dir)
      write_data(merged, merged_path)
      true
    end
  end
end
