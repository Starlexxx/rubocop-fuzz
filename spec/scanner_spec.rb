# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RuboCopFuzz::Scanner do
  let(:shards) { %w[slow fast].map { |name| RuboCopFuzz::Corpus::Shard.new(name: name, root: '/x', files: []) } }
  let(:variants) { (1..5).map { |i| RuboCopFuzz::ConfigGenerator::Variant.new(id: "v#{i}", yaml: '') } }
  let(:scanner) { described_class.new(rubocop_dir: '/r', shards: shards, variants: variants, workers: 1, timeout: 1) }

  it 'stops running a shard once it has timed out repeatedly' do
    allow(scanner).to receive(:run_job) do |variant, shard|
      type = shard.name == 'slow' ? 'timeout' : 'loop'
      { 'shard' => shard.name, 'config' => variant.id,
        'findings' => [{ 'type' => type, 'shard' => shard.name }] }
    end

    findings = scanner.scan

    expect(findings.count { |f| f['shard'] == 'slow' }).to eq(described_class::MAX_SHARD_TIMEOUTS)
    expect(findings.count { |f| f['shard'] == 'fast' }).to eq(5)
  end
end
