# frozen_string_literal: true

require 'yaml'

module RuboCopFuzz
  # Generates .rubocop.yml variants from RuboCop's own config/default.yml.
  #
  # baseline: defaults with pending cops enabled.
  # sweep: one variant per non-default EnforcedStyle* value and per flipped
  #   boolean cop option.
  # interactions: per cross-cop dependency cluster, the cartesian product of
  #   the cluster members' option axes.
  class ConfigGenerator
    Variant = Struct.new(:id, :yaml, keyword_init: true)

    SKIP_BOOLEAN_KEYS = %w[Enabled Safe SafeAutoCorrect AutoCorrect Include Exclude].freeze
    MAX_COMBOS_PER_CLUSTER = 200

    def initialize(rubocop_dir: nil, target_ruby_version: RUBY_VERSION[/\d+\.\d+/])
      @rubocop_dir = rubocop_dir
      @target_ruby_version = target_ruby_version
    end

    def baseline
      Variant.new(id: 'baseline', yaml: "#{all_cops_yaml}\n")
    end

    def sweep_variants
      cop_entries.flat_map { |cop, conf| axes_for(cop, conf) }
                 .map { |cop, opts| variant_for(cop, opts) }
    end

    def interaction_variants(clusters)
      clusters.flat_map do |cluster|
        combos_for(cluster).map do |combo|
          id = "cluster:#{cluster.join('+')}:#{combo_id(combo)}"
          Variant.new(id: id, yaml: cluster_yaml(cluster, combo))
        end
      end
    end

    private

    def defaults
      @defaults ||= YAML.unsafe_load_file(File.join(@rubocop_dir, 'config', 'default.yml'))
    end

    def cop_entries
      defaults.select { |key, value| key.include?('/') && value.is_a?(Hash) }
    end

    # Option axes for one cop: every non-default supported style value and
    # every flipped boolean, one axis entry per (cop, {option => value}).
    def axes_for(cop, conf)
      style_axes(cop, conf) + boolean_axes(cop, conf)
    end

    def style_axes(cop, conf)
      conf.flat_map do |key, values|
        next [] unless key.start_with?('Supported') && values.is_a?(Array)

        enforced = key.sub('Supported', 'Enforced').sub('Styles', 'Style')
        next [] unless conf.key?(enforced)

        (values - [conf[enforced]]).map { |style| [cop, { enforced => style }] }
      end
    end

    def boolean_axes(cop, conf)
      conf.filter_map do |key, value|
        next unless [true, false].include?(value) && !SKIP_BOOLEAN_KEYS.include?(key)

        [cop, { key => !value }]
      end
    end

    def variant_for(cop, opts)
      id = "#{cop}:#{opts.map { |k, v| "#{k}=#{v}" }.join(',')}"
      config = { cop => { 'Enabled' => true }.merge(opts) }
      Variant.new(id: id, yaml: "#{all_cops_yaml}\n#{config.to_yaml.delete_prefix("---\n")}")
    end

    # Cartesian product over cluster members' axes; each member also
    # contributes a "defaults" choice so partial combinations are covered.
    def combos_for(cluster)
      per_cop = cluster.map do |cop|
        conf = defaults[cop] || {}
        [[cop, {}]] + axes_for(cop, conf)
      end
      product = per_cop[0].product(*per_cop[1..])
      product.take(MAX_COMBOS_PER_CLUSTER)
    end

    def combo_id(combo)
      parts = combo.reject { |_cop, opts| opts.empty? }
      return 'defaults' if parts.empty?

      parts.map { |cop, opts| "#{cop}(#{opts.map { |k, v| "#{k}=#{v}" }.join(',')})" }.join('|')
    end

    def cluster_yaml(cluster, combo)
      config = combo.to_h { |cop, opts| [cop, { 'Enabled' => true }.merge(opts)] }
      "#{all_cops_yaml}\n#{config.to_yaml.delete_prefix("---\n")}"
    end

    def all_cops_yaml
      <<~YAML.chomp
        AllCops:
          NewCops: enable
          SuggestExtensions: false
          TargetRubyVersion: #{@target_ruby_version}
      YAML
    end
  end
end
