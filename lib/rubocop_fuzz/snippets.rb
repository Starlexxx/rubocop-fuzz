# frozen_string_literal: true

require 'prism'
require 'digest'
require 'fileutils'

module RuboCopFuzz
  # Turns the heredoc sources in cop specs into a corpus of small files.
  # Spec examples are full of the rare syntax and edge cases that real code
  # seldom has, and wrapping them in common surrounding contexts finds the
  # corrections that break once the code is no longer the whole file.
  class Snippets
    WRAPPERS = [
      "x = %s\n",
      "x ||= %s\n",
      "foo(%s)\n",
      "foo(%s, bar)\n",
      "foo(\n%s,\n)\n",
      "foo bar, %s\n",
      "[%s]\n",
      "{ key: %s }\n",
      "%s if condition\n",
      "condition ? %s : nil\n",
      "%s; other\n",
      "def m = %s\n",
      "-> { %s }\n",
      "foo do\n%s\nend\n",
      "begin\n%s\nend.bar\n",
      "\"\#{%s}\"\n"
    ].freeze

    ANNOTATION_LINE = /\A\s*\^/
    PLACEHOLDER = /%\{|\^\{|_\{/

    def initialize(spec_dirs, wrappers: 0, seed: 0)
      @spec_dirs = spec_dirs
      @wrappers = wrappers
      @seed = seed
    end

    def sources
      @sources ||= begin
        plain = spec_files.flat_map { |file| heredocs(file) }.uniq
        (plain + plain.flat_map { |source| wrapped(source) }).uniq
      end
    end

    def write(dir)
      FileUtils.mkdir_p(dir)
      sources.each do |source|
        File.write(File.join(dir, "#{Digest::SHA1.hexdigest(source)[0, 16]}.rb"), source)
      end
      sources.size
    end

    private

    def spec_files
      @spec_dirs.flat_map { |dir| Dir.glob(File.join(dir, '**', '*_spec.rb')) }.sort
    end

    def heredocs(file)
      nodes = [Prism.parse_file(file).value]
      found = []
      until nodes.empty?
        node = nodes.pop
        nodes.concat(node.compact_child_nodes)
        source = heredoc_source(node)
        found << source if source
      end
      found
    end

    # Squiggly heredocs come back as one string part per line; any real
    # interpolation needs the spec's context, so those are skipped.
    def heredoc_source(node)
      return unless node.is_a?(Prism::StringNode) || node.is_a?(Prism::InterpolatedStringNode)
      return unless node.opening_loc&.slice&.start_with?('<<')

      raw = if node.is_a?(Prism::StringNode)
              node.unescaped
            elsif node.parts.all?(Prism::StringNode)
              node.parts.map(&:unescaped).join
            end
      clean(raw) if raw&.valid_encoding?
    end

    def clean(raw)
      source = raw.lines.grep_v(ANNOTATION_LINE).join
      return if source.strip.empty? || source.match?(PLACEHOLDER)

      source if valid?(source)
    end

    def wrapped(source)
      return [] unless @wrappers.positive?

      picked = WRAPPERS.shuffle(random: Random.new(Digest::SHA1.hexdigest(source).to_i(16) + @seed))
      picked.lazy.map { |wrapper| format(wrapper, source.chomp) }.select { |s| valid?(s) }.first(@wrappers)
    end

    def valid?(source)
      Prism.parse(source).success?
    end
  end
end
