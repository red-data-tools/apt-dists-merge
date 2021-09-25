require "digest"
require "optparse"
require "zlib"

module APTDistsMerge
  class CommandLine
    def initialize(output=nil)
      @base_dir = nil
      @incomping_dir = nil
      @output_dir = nil
      @output = output || "-"
    end

    def run(args)
      catch do |tag|
        open_output do |output|
          parse_args(args, output, tag)
          process
        end
      end
    end

    private
    def open_output(&block)
      case @output
      when "-"
        yield($stdout)
      when String
        File.open(@output, "w", &block)
      else
        yield(@output)
      end
    end

    def parse_args(args, output, tag)
      parser = OptionParser.new
      parser.banner += " BASE_DIR INCOMING_DIR OUTPUT_DIR"
      parser.on("--version",
                "Show version and exit") do
        output.puts(VERSION)
        throw(tag, true)
      end
      parser.on("--help",
                "Show this message and exit") do
        output.puts(parser.help)
        throw(tag, true)
      end
      args = parser.parse!(args.dup)
      if args.size != 3
        $stderr.puts(parser.help)
        throw(tag, false)
      end
      @base_dir = args[0]
      @incoming_dir = args[1]
      @output_dir = args[2]
    end

    def process
      merger = Merger.new(@base_dir, @incoming_dir, @output_dir)
      merger.merge
    end
  end
end
