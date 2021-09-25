class CommandLineTest < Test::Unit::TestCase
  include Helper

  def setup
    Dir.mktmpdir do |dir|
      @dir = dir
      @code_name = "buster"
      @component = "main"
      @repository_label = "Red Data Tools"
      @repository_description = "Red Data Tools related packages"
      setup_pool
      setup_dists
      yield
    end
  end

  def setup_pool
    @package_dir = "pool/#{@component}/r/red-data-tools-archive-keyring"
    @base_dir = "#{@dir}/base"
    @incoming_dir = "#{@dir}/incoming"
    @all_dir = "#{@dir}/all"
    @base_package_dir = "#{@base_dir}/#{@package_dir}"
    @incoming_package_dir = "#{@incoming_dir}/#{@package_dir}"
    @all_package_dir = "#{@all_dir}/#{@package_dir}"
    FileUtils.mkdir_p(@base_package_dir)
    FileUtils.mkdir_p(@incoming_package_dir)
    FileUtils.mkdir_p(@all_package_dir)
    FileUtils.cp_r(Dir.glob(fixture_path(@package_dir, "*_2019.11.8*")),
                   @base_package_dir)
    FileUtils.cp_r(Dir.glob(fixture_path(@package_dir, "*_2020.3.13*")),
                   @incoming_package_dir)
    FileUtils.cp_r(Dir.glob("#{@base_package_dir}/*"),
                   @all_package_dir)
    FileUtils.cp_r(Dir.glob("#{@incoming_package_dir}/*"),
                   @all_package_dir)
  end

  def setup_dists
    @relative_dists_dir = "dists/#{@code_name}"
    @base_dists_dir = "#{@base_dir}/#{@relative_dists_dir}"
    @incoming_dists_dir = "#{@incoming_dir}/#{@relative_dists_dir}"
    @all_dists_dir = "#{@all_dir}/#{@relative_dists_dir}"
    setup_dist(@base_dir)
    setup_dist(@incoming_dir)
    setup_dist(@all_dir)
  end

  def system(*args)
    unless super
      raise "Failed to run command: #{args.join(" ")}"
    end
  end

  def generate_apt_release(dists_dir, architecture)
    dir = "#{dists_dir}/#{@component}/"
    if architecture == "source"
      dir << architecture
    else
      dir << "binary-#{architecture}"
    end

    FileUtils.mkdir_p(dir)
    File.open("#{dir}/Release", "w") do |release|
      release.puts(<<-RELEASE)
Archive: #{@code_name}
Component: #{@component}
Origin: #{@repository_label}
Label: #{@repository_label}
Architecture: #{architecture}
      RELEASE
    end
  end

  def generate_apt_ftp_archive_generate_conf(output)
    output.puts(<<-CONF)
Dir::ArchiveDir ".";
Dir::CacheDir ".";
TreeDefault::Directory "pool/#{@component}";
TreeDefault::SrcDirectory "pool/#{@component}";
Default::Packages::Extensions ".deb";
Default::Packages::Compress ". gzip xz";
Default::Sources::Compress ". gzip xz";

BinDirectory "#{@relative_dists_dir}/#{@component}/binary-amd64" {
  Packages "#{@relative_dists_dir}/#{@component}/binary-amd64/Packages";
  Contents "#{@relative_dists_dir}/#{@component}/Contents-amd64";
  SrcPackages "#{@relative_dists_dir}/#{@component}/source/Sources";
};

Tree "#{@relative_dists_dir}" {
  Sections "#{@component}";
  Architectures "amd64 source";
};
    CONF
  end

  def generate_apt_ftp_archive_release_conf(output)
    output.puts(<<-CONF)
APT::FTPArchive::Release::Origin "#{@repository_label}";
APT::FTPArchive::Release::Label "#{@repository_label}";
APT::FTPArchive::Release::Architectures "amd64";
APT::FTPArchive::Release::Codename "#{@code_name}";
APT::FTPArchive::Release::Suite "#{@code_name}";
APT::FTPArchive::Release::Components "#{@component}";
APT::FTPArchive::Release::Description "#{@repository_description}";
    CONF
  end

  def setup_dist(base_dir)
    dists_dir = "#{base_dir}/#{@relative_dists_dir}"

    generate_apt_release(dists_dir, "source")
    generate_apt_release(dists_dir, "amd64")

    generate_conf_file = Tempfile.new("apt-ftparchive-generate.conf")
    generate_apt_ftp_archive_generate_conf(generate_conf_file)
    generate_conf_file.close
    Dir.chdir(base_dir) do
      system("apt-ftparchive",
             "generate",
             generate_conf_file.path,
             err: File::NULL)
    end

    release_conf_file = Tempfile.new("apt-ftparchive-release.conf")
    generate_apt_ftp_archive_release_conf(release_conf_file)
    release_conf_file.close
    release_file = Tempfile.new("apt-ftparchive-release")
    system("apt-ftparchive",
           "-c", release_conf_file.path,
           "release",
           dists_dir,
           out: release_file.path)
    FileUtils.cp(release_file.path, "#{dists_dir}/Release")
  end

  def run_command(*args)
    output = StringIO.new
    command_line = APTDistsMerge::CommandLine.new(output)
    success = command_line.run(args)
    [success, output.string]
  end

  def read_content(path)
    return nil unless File.exist?(path)
    case File.extname(path)
    when ".gz"
      Zlib::GzipReader.open(path) do |input|
        input.read
      end
    when ".xz"
      IO.popen(["xz", "--decompress", "--stdout", path]) do |input|
        input.read
      end
    else
      File.read(path)
    end
  end

  def extract_date(deb822)
    deb822[/Date: (.+)$/, 1]
  end

  def normalize_release(release, normalized_date)
    return nil if release.nil?
    if normalized_date
      release = release.gsub(/^Date: .+$/) {"Date: #{normalized_date}"}
    end
    release = release.gsub(/^ (\h+) ([ \d]{16}) (.+)$/) do
      checksum = $1
      size = $2
      file = $3
      case File.extname(file)
      when ".gz", ".xz"
        checksum = "0" * checksum.size
        size = "%*d" % [size.size, 0]
      end
      " #{checksum} #{size} #{file}"
    end
    release
  end

  def test_merge
    output_dists_dir = "#{@dir}/output/#{@relative_dists_dir}"
    assert_equal([true, ""],
                 run_command("#{@base_dir}/#{@relative_dists_dir}",
                             "#{@incoming_dir}/#{@relative_dists_dir}",
                             output_dists_dir))
    incoming_release_path =
      "#{@incoming_dir}/#{@relative_dists_dir}/Release"
    incoming_date = extract_date(read_content(incoming_release_path))
    assert_equal(
      [
        normalize_release(read_content("#{@all_dists_dir}/Release"),
                          incoming_date),
        read_content("#{@all_dists_dir}/main/Contents-amd64.gz"),
        read_content("#{@all_dists_dir}/main/binary-amd64/Packages"),
        read_content("#{@all_dists_dir}/main/binary-amd64/Packages.gz"),
        read_content("#{@all_dists_dir}/main/binary-amd64/Packages.xz"),
        read_content("#{@all_dists_dir}/main/binary-amd64/Release"),
        read_content("#{@all_dists_dir}/main/source/Release"),
        read_content("#{@all_dists_dir}/main/source/Sources"),
        read_content("#{@all_dists_dir}/main/source/Sources.gz"),
        read_content("#{@all_dists_dir}/main/source/Sources.xz"),
      ],
      [
        normalize_release(read_content("#{output_dists_dir}/Release"), nil),
        read_content("#{output_dists_dir}/main/Contents-amd64.gz"),
        read_content("#{output_dists_dir}/main/binary-amd64/Packages"),
        read_content("#{output_dists_dir}/main/binary-amd64/Packages.gz"),
        read_content("#{output_dists_dir}/main/binary-amd64/Packages.xz"),
        read_content("#{output_dists_dir}/main/binary-amd64/Release"),
        read_content("#{output_dists_dir}/main/source/Release"),
        read_content("#{output_dists_dir}/main/source/Sources"),
        read_content("#{output_dists_dir}/main/source/Sources.gz"),
        read_content("#{output_dists_dir}/main/source/Sources.xz"),
      ])
  end
end
