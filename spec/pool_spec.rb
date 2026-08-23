# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RuboCopFuzz::Pool do
  it 'runs every job in a child process and preserves order' do
    results = described_class.new(size: 3).run([1, 2, 3, 4, 5]) do |job|
      { 'square' => job * job, 'pid' => Process.pid }
    end

    expect(results.map { |r| r['square'] }).to eq([1, 4, 9, 16, 25])
    expect(results.map { |r| r['pid'] }).not_to include(Process.pid)
  end

  it 'reports a dead worker instead of raising' do
    results = described_class.new(size: 2).run([:ok, :die]) do |job|
      exit!(1) if job == :die
      { 'ok' => true }
    end

    expect(results[0]).to eq('ok' => true)
    expect(results[1]['error']).to match(/worker died/)
  end

  it 'invokes the progress callback per finished job' do
    seen = []
    described_class.new(size: 2).run([1, 2], progress: ->(idx, _r) { seen << idx }) do |job|
      { 'job' => job }
    end

    expect(seen.sort).to eq([0, 1])
  end
end
