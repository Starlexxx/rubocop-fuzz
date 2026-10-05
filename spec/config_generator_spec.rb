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

  describe '#packed_variants' do
    let(:variants) { generator.packed_variants(seed: 1) }
    let(:configs) { variants.map { |v| YAML.safe_load(v.yaml) } }

    it 'needs only as many variants as the longest list of alternatives' do
      expect(variants.size).to eq(1)
    end

    it 'enables every cop in every variant, including ones disabled by default' do
      configs.each do |config|
        expect(config['Style/Foo']).to include('Enabled' => true)
        expect(config['Layout/Bar']).to include('Enabled' => true)
      end
    end

    it 'leaves cops that contradict enabled-by-default ones at their defaults' do
      File.write(File.join(@rubocop_dir, 'config', 'default.yml'), <<~YAML)
        Style/MissingElse:
          Enabled: false
          EnforcedStyle: both
          SupportedStyles: [if, case, both]
      YAML

      expect(configs).to all(satisfy { |c| !c.key?('Style/MissingElse') })
    end

    it 'covers every non-default option value across the variants' do
      expect(configs.map { |c| c['Style/Foo']['EnforcedStyle'] }).to include('expanded')
      expect(configs.map { |c| c['Style/Foo']['AllowComments'] }).to include(true)
      expect(configs.map { |c| c['Layout/Bar']['AllowMultiline'] }).to include(false)
    end

    it 'spreads the alternatives of a many-valued option over several variants' do
      File.write(File.join(@rubocop_dir, 'config', 'default.yml'), <<~YAML)
        Style/Foo:
          Enabled: true
          EnforcedStyle: a
          SupportedStyles: [a, b, c, d]
        Style/Baz:
          Enabled: true
          EnforcedStyle: x
          SupportedStyles: [x, y]
      YAML

      styles = configs.map { |c| c['Style/Foo']['EnforcedStyle'] }
      expect(styles).to contain_exactly('b', 'c', 'd')
      expect(configs.map { |c| c['Style/Baz']['EnforcedStyle'] }.compact).to eq(['y'])
    end

    it 'pairs the options differently for a different seed' do
      File.write(File.join(@rubocop_dir, 'config', 'default.yml'), <<~YAML)
        Style/Foo:
          Enabled: true
          EnforcedStyle: a
          SupportedStyles: [a, b, c, d, e, f]
        Style/Baz:
          Enabled: true
          EnforcedStyle: x
          SupportedStyles: [x, y]
      YAML

      pairing = lambda do |seed|
        generator = described_class.new(rubocop_dir: @rubocop_dir, target_ruby_version: '3.3')
        generator.packed_variants(seed: seed).map do |v|
          YAML.safe_load(v.yaml).values_at('Style/Foo', 'Style/Baz').map { |c| c['EnforcedStyle'] }
        end
      end

      expect(pairing.call(1)).to eq(pairing.call(1))
      expect((1..20).map { |seed| pairing.call(seed) }.uniq.size).to be > 1
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
