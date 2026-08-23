# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

module RuboCopFuzz
  # Runs (config variant x corpus shard) jobs through the pool and
  # turns RuboCop output into findings.
  class Scanner
    RUBOCOP_ARGS = %w[-A --cache false --no-color -f quiet].freeze

    def initialize(rubocop_dir:, shards:, variants:, workers:, timeout:)
      @rubocop_dir = rubocop_dir
      @shards = shards
      @variants = variants
      @workers = workers
      @timeout = timeout
    end

    def scan(progress: nil)
      jobs = @variants.product(@shards)
      results = Pool.new(size: @workers).run(jobs, progress: progress) do |(variant, shard)|
        run_job(variant, shard)
      end
      results.flat_map { |r| r&.fetch('findings', []) || [] }
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

        findings.each { |f| f.merge!(shard: shard.name, config: variant.id) }
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
  end
end
