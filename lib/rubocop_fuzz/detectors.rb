# frozen_string_literal: true

module RuboCopFuzz
  # Parses RuboCop output for cop crashes and infinite correction loops.
  module Detectors
    CRASH_RE = /^An error occurred while (?<cop>\S+) cop was inspecting (?<location>.+)\.$/
    LOOP_RE = /^Infinite loop detected in (?<file>.+?)(?: and caused by (?<cops>.+))?$/
    ERROR_LINE_RE = /\((?<klass>[A-Z]\w*(?:::[A-Z]\w*)*)\)\s*$/

    module_function

    def scan_stderr(stderr)
      stderr.each_line.filter_map do |line|
        line = line.chomp
        if (m = line.match(CRASH_RE))
          { type: 'crash', cops: [m[:cop]], location: m[:location] }
        elsif (m = line.match(LOOP_RE))
          cops = parse_loop_cops(m[:cops])
          { type: 'loop', cops: cops, location: m[:file],
            signature: "loop:#{cops.sort.join('+')}" }
        end
      end
    end

    def parse_loop_cops(chain)
      return [] unless chain

      chain.split(/\s*->\s*/).flat_map { |part| part.split(/,\s*/) }.map(&:strip).uniq
    end

    # Dedupe signature from `rubocop -d` output: error class + message,
    # paths and numbers normalized away.
    def crash_signature(cop, debug_output)
      line = debug_output.each_line.find { |l| l.match?(ERROR_LINE_RE) }
      return "unreproduced:#{cop}" unless line

      klass = line.match(ERROR_LINE_RE)[:klass]
      message = line.sub(ERROR_LINE_RE, '').sub(/\A\S+:\d+:in [^:]+:\s*/, '').strip
      normalized = message.gsub(%r{(?:/[\w.@-]+)+}, '<path>').gsub(/\d+/, 'N')
      "#{cop}: #{klass}: #{normalized}"
    end
  end
end
