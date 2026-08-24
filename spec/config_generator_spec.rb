# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'tmpdir'
require 'fileutils'

RSpec.describe RuboCopFuzz::ConfigGenerator do
  around do |example|
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'config'))
      File.write(File.join(dir, 'config', 'default.yml'), <<~YAML)
        AllCops:
          NewCops: pending
        Style/Foo:
          Enabled: true
          EnforcedStyle: compact
          SupportedStyles:
            - compact
            - expanded
          AllowComments: false
        Layout/Bar:
          Enabled: false
          AllowMultiline: true
      YAML
      @rubocop_dir = dir
      example.run
    end
  end

  let(:generator) { described_class.new(rubocop_dir: @rubocop_dir, target_ruby_version: '3.3') }

  it 'produces a baseline variant with pending cops enabled' do
    config = YAML.safe_load(generator.baseline.yaml)
    expect(config['AllCops']).to include('NewCops' => 'enable', 'SuggestExtensions' => false)
  end

  describe '#sweep_variants' do
    it 'generates one variant per non-default style and per flipped boolean' do
      ids = generator.sweep_variants.map(&:id)
      expect(ids).to contain_exactly(
        'Style/Foo:EnforcedStyle=expanded',
        'Style/Foo:AllowComments=true',
        'Layout/Bar:AllowMultiline=false'
      )
    end

    it 'forces the cop on and applies the option' do
      variant = generator.sweep_variants.find { |v| v.id == 'Layout/Bar:AllowMultiline=false' }
      config = YAML.safe_load(variant.yaml)
      expect(config['Layout/Bar']).to eq('Enabled' => true, 'AllowMultiline' => false)
    end
  end

  describe '#interaction_variants' do
    it 'builds the cartesian product of cluster member axes including defaults' do
      variants = generator.interaction_variants([%w[Style/Foo Layout/Bar]])

      expect(variants.size).to eq(6)
      expect(variants.map(&:id)).to include('cluster:Style/Foo+Layout/Bar:defaults')

      combo = variants.find { |v| v.id.include?('EnforcedStyle=expanded') && v.id.include?('AllowMultiline=false') }
      config = YAML.safe_load(combo.yaml)
      expect(config['Style/Foo']).to include('Enabled' => true, 'EnforcedStyle' => 'expanded')
      expect(config['Layout/Bar']).to eq('Enabled' => true, 'AllowMultiline' => false)
    end
  end
end
