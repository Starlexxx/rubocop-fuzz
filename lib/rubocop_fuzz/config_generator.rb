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
    PACKED_EXCLUDED_COPS = %w[
      Style/MissingElse Style/StringHashKeys RSpec/AlignLeftLetBrace RSpec/AlignRightLetBrace
    ].freeze
    TARGET_RAILS_VERSION = 8.0

    def initialize(rubocop_dir: nil, plugins: {}, target_ruby_version: RUBY_VERSION[/\d+\.\d+/])
      @rubocop_dir = rubocop_dir
      @plugins = plugins
      @target_ruby_version = target_ruby_version
    end

    def baseline
      Variant.new(id: 'baseline', yaml: "#{all_cops_yaml}\n")
    end

    def sweep_variants
      cop_entries.flat_map { |cop, conf| axes_for(cop, conf) }
                 .map { |cop, opts| variant_for(cop, opts) }
    end

    def packed_variants(seed:)
      rng = Random.new(seed)
      cops = cop_entries.reject { |cop, _conf| PACKED_EXCLUDED_COPS.include?(cop) }
      options = cops.flat_map { |cop, conf| axes_for(cop, conf) }
                    .group_by { |cop, opts| [cop, opts.keys.first] }
      count = [options.values.map(&:size).max || 0, 1].max
      slots = Array.new(count) { cops.keys.to_h { |cop| [cop, { 'Enabled' => true }] } }

      options.each_value do |alternatives|
        offset = rng.rand(count)
        alternatives.shuffle(random: rng).each_with_index do |(cop, opts), i|
          slots[(offset + i) % count][cop].merge!(opts)
        end
      end

      slots.each_with_index.map do |config, i|
        Variant.new(id: "packed:#{seed}:#{i}",
                    yaml: "#{all_cops_yaml}\n#{config.to_yaml.delete_prefix("---\n")}")
      end
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
      @defaults ||= [@rubocop_dir, *@plugins.values].map { |dir| default_yml(dir) }.reduce do |merged, plugin|
        merged.merge(plugin) { |_cop, core, over| core.is_a?(Hash) && over.is_a?(Hash) ? core.merge(over) : over }
      end
    end

    def default_yml(dir)
      YAML.unsafe_load_file(File.join(dir, 'config', 'default.yml'))
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
        #{plugins_yaml}AllCops:
          NewCops: enable
          SuggestExtensions: false
          TargetRubyVersion: #{@target_ruby_version}#{rails_yaml}
      YAML
    end

    # Copied shards have no Gemfile.lock, so rubocop-rails would fall back
    # to Rails 5.0 and skip every cop gated on a newer version.
    def rails_yaml
      @plugins.key?('rubocop-rails') ? "\n  TargetRailsVersion: #{TARGET_RAILS_VERSION}" : ''
    end

    def plugins_yaml
      return '' if @plugins.empty?

      "plugins:\n#{@plugins.keys.map { |name| "  - #{name}\n" }.join}"
    end
  end
end
