# frozen_string_literal: true

require 'yaml'
require 'tmpdir'
require 'fileutils'

module RuboCopFuzz
  # Shrinks a finding to a minimal repro via delta debugging:
  # the enabled cop set, then non-default options, then source lines.
  class Minimizer
    Repro = Struct.new(:cops, :cop_configs, :source, :yaml, keyword_init: true)

    def initialize(rubocop_dir:, timeout: 60)
      @rubocop_dir = rubocop_dir
      @invoker = Invoker.new(rubocop_dir: rubocop_dir, timeout: timeout)
    end

    def minimize(finding)
      return nil unless finding['file'] && File.exist?(finding['file'])

      source = File.read(finding['file'])
      cop_configs = explicit_cop_configs(finding['config_yaml'].to_s)
      cops = (finding['cops'] + cop_configs.keys).uniq

      return nil unless fails?(cops, cop_configs, source, finding)

      cops = ddmin(cops) { |subset| fails?(subset, cop_configs, source, finding) }
      cop_configs = minimize_options(cops, cop_configs, source, finding)
      lines = ddmin(source.lines) { |ls| fails?(cops, cop_configs, ls.join, finding) }
      source = lines.join

      Repro.new(cops: cops, cop_configs: cop_configs.slice(*cops),
                source: source, yaml: repro_yaml(cops, cop_configs))
    end

    private

    # Cop entries the config variant sets explicitly (everything except AllCops).
    def explicit_cop_configs(yaml)
      (YAML.safe_load(yaml) || {}).except('AllCops')
        .transform_values { |conf| (conf || {}).except('Enabled') }
    rescue Psych::SyntaxError
      {}
    end

    def repro_yaml(cops, cop_configs)
      config = { 'AllCops' => { 'DisabledByDefault' => true, 'SuggestExtensions' => false } }
      cops.sort.each do |cop|
        config[cop] = { 'Enabled' => true }.merge(cop_configs[cop] || {})
      end
      config.to_yaml.delete_prefix("---\n")
    end

    def fails?(cops, cop_configs, source, finding)
      return false if cops.empty? || source.strip.empty?

      Dir.mktmpdir('fuzz-min-') do |dir|
        File.write(File.join(dir, 'repro.rb'), source)
        File.write(File.join(dir, '.rubocop.yml'), repro_yaml(cops, cop_configs))
        result = @invoker.run(%w[-A --cache false --no-color -f quiet repro.rb], chdir: dir)
        reproduces?(result, finding)
      end
    end

    def reproduces?(result, finding)
      case finding['type']
      when 'loop'
        result.stderr.include?('Infinite loop detected')
      when 'crash'
        cop = finding['cops'].first
        result.stderr.include?("An error occurred while #{cop} cop")
      when 'timeout'
        result.timeout?
      else
        false
      end
    end

    # Revert each non-default option in turn; keep the reverts that still fail.
    def minimize_options(cops, cop_configs, source, finding)
      current = cop_configs.slice(*cops).transform_values(&:dup)
      current.each do |cop, opts|
        opts.keys.each do |key|
          candidate = current.merge(cop => opts.except(key))
          if fails?(cops, candidate, source, finding)
            current = candidate
            opts.delete(key)
          end
        end
      end
      current
    end

    def ddmin(items, &fails)
      granularity = 2
      while items.size >= 2
        chunks = each_chunk(items, granularity)
        candidate = chunks.map { |chunk| items - chunk }.find { |c| fails.call(c) }

        if candidate
          items = candidate
          granularity = [granularity - 1, 2].max
        else
          break if granularity >= items.size

          granularity = [granularity * 2, items.size].min
        end
      end
      items
    end

    def each_chunk(items, granularity)
      size = (items.size.to_f / granularity).ceil
      items.each_slice(size).to_a
    end
  end
end
