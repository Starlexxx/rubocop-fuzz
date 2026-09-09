# frozen_string_literal: true

require 'optparse'
require 'etc'
require 'json'

module RuboCopFuzz
  class CLI
    DEFAULTS = {
      rubocop_dir: nil,
      gems_dir: File.join(Gem.dir, 'gems'),
      out_dir: 'fuzz-out',
      workers: Etc.nprocessors,
      timeout: 600,
      shard_limit: nil,
      shard_filter: nil,
      tiers: ['baseline'],
      shards_per_config: nil
    }.freeze

    def run(argv)
      command = argv.shift
      case command
      when 'scan' then scan(argv)
      when 'minimize' then minimize(argv)
      when 'triage' then triage(argv)
      else
        warn 'usage: rubocop-fuzz scan|minimize|triage --rubocop DIR [options]'
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
      variants = build_variants(opts)
      total = if opts[:shards_per_config]
                variants.size * [opts[:shards_per_config], shards.size].min
              else
                shards.size * variants.size
              end
      puts "#{shards.size} shards x #{variants.size} config(s) = ~#{total} jobs, " \
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
                            workers: opts[:workers], timeout: opts[:timeout],
                            shards_per_config: opts[:shards_per_config])
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
        o.on('--tier TIERS', 'baseline,sweep,interactions') { |v| opts[:tiers] = v.split(',') }
        o.on('--shards-per-config N', Integer) { |v| opts[:shards_per_config] = v }
        o.on('--config-filter REGEX') { |v| opts[:config_filter] = Regexp.new(v) }
        o.on('--shard-slice I/N', %r{\A\d+/\d+\z}, 'take shard subset i of n') do |v|
          i, n = v.split('/').map(&:to_i)
          opts[:shard_slice] = [i, n]
        end
      end.parse!(argv)
      opts
    end

    def minimize(argv)
      opts = { findings: 'fuzz-out/findings.jsonl', timeout: 60 }
      OptionParser.new do |o|
        o.on('--rubocop DIR') { |v| opts[:rubocop_dir] = v }
        o.on('--findings PATH') { |v| opts[:findings] = v }
        o.on('--timeout SECS', Integer) { |v| opts[:timeout] = v }
      end.parse!(argv)

      unless opts[:rubocop_dir] && File.exist?(opts[:findings])
        warn 'error: --rubocop DIR and a findings file are required'
        return 1
      end

      minimizer = Minimizer.new(rubocop_dir: File.expand_path(opts[:rubocop_dir]),
                                timeout: opts[:timeout])
      findings = File.readlines(opts[:findings]).map { |l| JSON.parse(l) }
                     .uniq { |f| [f['type'], f['cops'].sort, f['signature']] }

      findings.each_with_index do |finding, i|
        puts "## #{i + 1}. [#{finding['type']}] #{finding['cops'].join(', ')}"
        repro = minimizer.minimize(finding)
        if repro.nil?
          puts "not reproduced\n\n"
          next
        end
        puts <<~MD

          Cops: #{repro.cops.join(', ')}

          ```ruby
          #{repro.source.chomp}
          ```

          ```yaml
          #{repro.yaml.chomp}
          ```

          ```
          rubocop -A --cache false repro.rb
          ```

        MD
      end
      0
    end

    def triage(argv)
      opts = { findings: 'fuzz-out/findings.jsonl', known: 'known_issues.yml', out: nil }
      OptionParser.new do |o|
        o.on('--findings PATH') { |v| opts[:findings] = v }
        o.on('--known PATH') { |v| opts[:known] = v }
        o.on('--out PATH') { |v| opts[:out] = v }
      end.parse!(argv)

      unless File.exist?(opts[:findings])
        warn "error: findings file not found: #{opts[:findings]}"
        return 1
      end

      findings = File.readlines(opts[:findings]).map { |l| JSON.parse(l) }
      body = Triage.new(findings, known_path: opts[:known]).body
      opts[:out] ? File.write(opts[:out], body) : puts(body)
      0
    end

    def build_variants(opts)
      generator = ConfigGenerator.new(rubocop_dir: File.expand_path(opts[:rubocop_dir]))
      variants = opts[:tiers].flat_map do |tier|
        case tier
        when 'baseline' then [generator.baseline]
        when 'sweep' then generator.sweep_variants
        when 'interactions'
          clusters = DependencyMiner.new(File.expand_path(opts[:rubocop_dir])).clusters
          generator.interaction_variants(clusters)
        else
          warn "unknown tier: #{tier}"
          []
        end
      end
      variants = variants.select { |v| v.id.match?(opts[:config_filter]) } if opts[:config_filter]
      variants
    end

    def build_shards(opts)
      shards = Corpus.new(opts[:gems_dir]).shards
      shards = shards.select { |s| s.name.match?(opts[:shard_filter]) } if opts[:shard_filter]
      if (i, n = opts[:shard_slice])
        shards = shards.each_with_index.select { |_s, idx| idx % n == i }.map(&:first)
      end
      shards = shards.take(opts[:shard_limit]) if opts[:shard_limit]
      shards
    end
  end
end
