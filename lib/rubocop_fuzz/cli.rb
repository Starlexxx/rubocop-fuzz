# frozen_string_literal: true

require 'optparse'
require 'etc'

module RuboCopFuzz
  class CLI
    DEFAULTS = {
      rubocop_dir: nil,
      gems_dir: File.join(Gem.dir, 'gems'),
      out_dir: 'fuzz-out',
      workers: Etc.nprocessors,
      timeout: 600,
      shard_limit: nil,
      shard_filter: nil
    }.freeze

    def run(argv)
      command = argv.shift
      case command
      when 'scan' then scan(argv)
      else
        warn "usage: rubocop-fuzz scan --rubocop DIR [options]"
        command == 'help' ? 0 : 1
      end
    end

    private

    def scan(argv)
      opts = parse_options(argv)
      unless opts[:rubocop_dir] && File.directory?(opts[:rubocop_dir])
        warn 'error: --rubocop DIR (path to rubocop checkout) is required'
        return 1
      end

      shards = build_shards(opts)
      variants = ConfigGenerator.new.variants
      total = shards.size * variants.size
      puts "#{shards.size} shards x #{variants.size} config(s) = #{total} jobs, " \
           "#{opts[:workers]} workers, timeout #{opts[:timeout]}s"

      done = 0
      progress = lambda do |_idx, result|
        done += 1
        found = result&.fetch('findings', [])&.size.to_i
        marker = found.positive? ? " FOUND #{found}" : ''
        puts format('[%d/%d] %s (%ss)%s', done, total,
                    result && "#{result['shard']}/#{result['config']}" || '?',
                    result&.fetch('duration', '?'), marker)
      end

      scanner = Scanner.new(rubocop_dir: File.expand_path(opts[:rubocop_dir]),
                            shards: shards, variants: variants,
                            workers: opts[:workers], timeout: opts[:timeout])
      findings = scanner.scan(progress: progress)

      files = Report.new(findings, out_dir: opts[:out_dir],
                         rubocop_dir: File.expand_path(opts[:rubocop_dir])).write
      puts "\n#{findings.size} findings -> #{files.join(', ')}"
      0
    end

    def parse_options(argv)
      opts = DEFAULTS.dup
      OptionParser.new do |o|
        o.on('--rubocop DIR') { |v| opts[:rubocop_dir] = v }
        o.on('--gems-dir DIR') { |v| opts[:gems_dir] = v }
        o.on('--out DIR') { |v| opts[:out_dir] = v }
        o.on('--workers N', Integer) { |v| opts[:workers] = v }
        o.on('--timeout SECS', Integer) { |v| opts[:timeout] = v }
        o.on('--shard-limit N', Integer) { |v| opts[:shard_limit] = v }
        o.on('--shard-filter REGEX') { |v| opts[:shard_filter] = Regexp.new(v) }
      end.parse!(argv)
      opts
    end

    def build_shards(opts)
      shards = Corpus.new(opts[:gems_dir]).shards
      shards = shards.select { |s| s.name.match?(opts[:shard_filter]) } if opts[:shard_filter]
      shards = shards.take(opts[:shard_limit]) if opts[:shard_limit]
      shards
    end
  end
end
