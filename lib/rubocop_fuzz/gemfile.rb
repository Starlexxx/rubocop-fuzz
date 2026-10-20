# frozen_string_literal: true

require 'tmpdir'

module RuboCopFuzz
  # Gemfile for the checkouts under test. Without plugins it is the core
  # checkout's own; with plugins a generated one that points bundler at
  # every checkout by path, resolved once up front so forked workers never
  # race on resolution.
  class Gemfile
    def initialize(rubocop_dir:, plugins: {})
      @rubocop_dir = rubocop_dir
      @plugins = plugins
    end

    def path
      @path ||= @plugins.empty? ? File.join(@rubocop_dir, 'Gemfile') : generate
    end

    def source
      lines = ["source 'https://rubygems.org'", "gem 'rubocop', path: '#{@rubocop_dir}'"]
      @plugins.each { |name, dir| lines << "gem '#{name}', path: '#{dir}'" }
      "#{lines.join("\n")}\n"
    end

    private

    def generate
      dir = Dir.mktmpdir('fuzz-gemfile-')
      gemfile = File.join(dir, 'Gemfile')
      File.write(gemfile, source)
      raise Error, "bundle install failed for #{gemfile}" unless lock(gemfile) || install(gemfile)

      gemfile
    end

    def lock(gemfile)
      bundle(gemfile, 'lock', '--local')
    end

    def install(gemfile)
      bundle(gemfile, 'install')
    end

    def bundle(gemfile, *args)
      system({ 'BUNDLE_GEMFILE' => gemfile }, 'bundle', *args, out: File::NULL, err: File::NULL)
    end
  end
end
