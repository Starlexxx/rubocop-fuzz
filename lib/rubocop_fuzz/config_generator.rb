# frozen_string_literal: true

module RuboCopFuzz
  class ConfigGenerator
    Variant = Struct.new(:id, :yaml, keyword_init: true)

    def initialize(target_ruby_version: RUBY_VERSION[/\d+\.\d+/])
      @target_ruby_version = target_ruby_version
    end

    def variants
      [baseline]
    end

    def baseline
      Variant.new(id: 'baseline', yaml: <<~YAML)
        AllCops:
          NewCops: enable
          SuggestExtensions: false
          TargetRubyVersion: #{@target_ruby_version}
      YAML
    end
  end
end
