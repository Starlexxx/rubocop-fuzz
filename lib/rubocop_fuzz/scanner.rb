# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

module RuboCopFuzz
  # Runs (config variant x corpus shard) jobs through the pool and
  # turns RuboCop output into findings.
  class Scanner
    RUBOCOP_ARGS = %w[-A --cache false --no-color -f json].freeze

    def initialize(rubocop_dir:, shards:, variants:, workers:, timeout:, shards_per_config: nil)
      @rubocop_dir = rubocop_dir
      @shards = shards
      @variants = variants
      @workers = workers
      @timeout = timeout
      @shards_per_config = shards_per_config
    end

    def scan(progress: nil)
      jobs = build_jobs
      results = Pool.new(size: @workers).run(jobs, progress: progress) do |(variant, shard)|
        run_job(variant, shard)
      end
      results.flat_map { |r| r&.fetch('findings', []) || [] }
    end

    # Rotating window over the corpus so a large variant set still touches
    # every shard across the run without a full cartesian product.
    def build_jobs
      return @variants.product(@shards) unless @shards_per_config

      @variants.each_with_index.flat_map do |variant, i|
        picked = (0...@shards_per_config).map do |k|
          @shards[(i * @shards_per_config + k) % @shards.size]
        end
        picked.uniq.map { |shard| [variant, shard] }
      end
    end

    def run_job(variant, shard)
      Dir.mktmpdir("fuzz-#{shard.name.tr('/', '-')}-") do |dir|
        copy_shard(shard, dir)
        File.write(File.join(dir, '.rubocop.yml'), variant.yaml)
        result = invoker.run(RUBOCOP_ARGS, chdir: dir)

        findings =
          if result.timeout?
            [{ type: 'timeout', cops: [], signature: "timeout:#{shard.name}",
               duration: result.duration.round(1) }]
          else
            annotate(Detectors.scan_stderr(result.stderr).uniq, shard, dir, variant)
          end

        if !result.timeout? && findings.none? { |f| f[:type] == 'loop' }
          corrected_by_file = Detectors.corrected_offenses(result.stdout).group_by { |c| c[:file] }
          findings.concat(syntax_findings(shard, dir, corrected_by_file))
          findings.concat(idempotency_findings(shard, dir))
        end

        findings.each do |f|
          f.merge!(shard: shard.name, config: variant.id, config_yaml: variant.yaml)
        end
        { 'shard' => shard.name, 'config' => variant.id, 'duration' => result.duration.round(1),
          'findings' => findings }
      end
    end

    private

    def invoker
      @invoker ||= Invoker.new(rubocop_dir: @rubocop_dir, timeout: @timeout)
    end

    def copy_shard(shard, dir)
      shard.files.zip(shard.relative_files).each do |src, rel|
        dest = File.join(dir, rel)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(src, dest)
      end
    end

    def annotate(findings, shard, dir, variant)
      real_dir = File.realpath(dir)
      findings.each do |f|
        rel = f[:location].to_s.sub(/:\d+(:\d+)?\z/, '')
                          .delete_prefix("#{real_dir}/").delete_prefix("#{dir}/")
        f[:file] = File.join(shard.root, rel)
        f[:signature] ||= reproduce_crash(f, shard, rel, variant)
      end
    end

    # Rerun the crashing file alone with -d to get a backtrace.
    # Needs a fresh copy: the first pass may have already corrected it.
    def reproduce_crash(finding, shard, rel, variant)
      src = File.join(shard.root, rel)
      cop = finding[:cops].first
      return "unreproduced:#{cop}" unless File.exist?(src)

      Dir.mktmpdir('fuzz-repro-') do |dir|
        dest = File.join(dir, File.basename(rel))
        FileUtils.cp(src, dest)
        File.write(File.join(dir, '.rubocop.yml'), variant.yaml)
        result = invoker.run(['-A', '-d', '--cache', 'false', '--no-color', '-f', 'quiet',
                              File.basename(rel)], chdir: dir)
        Detectors.crash_signature(cop, result.stdout + result.stderr)
      end
    end

    # Corrected output must still parse. A file that no longer parses but
    # whose original does means autocorrect broke it.
    def syntax_findings(shard, dir, corrected_by_file)
      real_dir = File.realpath(dir)
      broken = SyntaxCheck.broken_files(Dir.glob(File.join(dir, '**', '*.rb')))
      broken.filter_map do |b|
        rel = b[:file].delete_prefix("#{real_dir}/").delete_prefix("#{dir}/")
        orig = File.join(shard.root, rel)
        next unless File.exist?(orig) && SyntaxCheck.broken_files([orig]).empty?

        cops = (corrected_by_file[rel] || []).map { |c| c[:cop] }.uniq.sort
        { type: 'broken_autocorrect', cops: cops, file: orig,
          signature: "syntax:#{Detectors.normalize(b[:error].to_s)}" }
      end
    end

    # A second `-A` pass over corrected output must correct nothing.
    def idempotency_findings(shard, dir)
      result = invoker.run(%w[-A --cache false --no-color -f json], chdir: dir)
      return [] if result.timeout?

      loops = Detectors.scan_stderr(result.stderr).uniq.select { |f| f[:type] == 'loop' }
      return annotate(loops, shard, dir, nil) unless loops.empty?

      corrected = Detectors.corrected_offenses(result.stdout)
      return [] if corrected.empty?

      cops = corrected.map { |c| c[:cop] }.uniq.sort
      files = corrected.map { |c| File.join(shard.root, c[:file]) }.uniq.take(3)
      [{ type: 'non_idempotent', cops: cops, signature: "nonidem:#{cops.join('+')}",
         file: files.first, files: files }]
    end
  end
end
