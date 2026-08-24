# frozen_string_literal: true

require 'open3'
require 'json'

module RuboCopFuzz
  # Checks Ruby files for syntax validity in a subprocess.
  module SyntaxCheck
    SCRIPT = <<~RUBY
      require 'json'
      bad = ARGV.filter_map do |f|
        begin
          RubyVM::AbstractSyntaxTree.parse(File.read(f))
          nil
        rescue SyntaxError => e
          { file: f, error: e.message.lines.first.to_s.strip }
        rescue StandardError
          nil
        end
      end
      print JSON.generate(bad)
    RUBY

    module_function

    def broken_files(files)
      return [] if files.empty?

      out, = Open3.capture3(RbConfig.ruby, '-e', SCRIPT, '--', *files)
      JSON.parse(out, symbolize_names: true)
    rescue JSON::ParserError
      []
    end
  end
end
