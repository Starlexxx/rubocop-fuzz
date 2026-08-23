# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe RuboCopFuzz::ConfigGenerator do
  it 'produces a baseline variant with pending cops enabled' do
    variant = described_class.new(target_ruby_version: '3.3').baseline
    config = YAML.safe_load(variant.yaml)

    expect(variant.id).to eq('baseline')
    expect(config['AllCops']).to include(
      'NewCops' => 'enable',
      'SuggestExtensions' => false,
      'TargetRubyVersion' => 3.3
    )
  end

  it 'includes the baseline in variants' do
    expect(described_class.new.variants.map(&:id)).to eq(['baseline'])
  end
end
