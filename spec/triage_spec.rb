# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RuboCopFuzz::Triage do
  let(:findings) do
    [
      { 'type' => 'loop', 'cops' => %w[Style/A Style/B],
        'signature' => 'loop:Style/A+Style/B', 'file' => 'a.rb' },
      { 'type' => 'loop', 'cops' => %w[Style/A Style/B],
        'signature' => 'loop:Style/A+Style/B', 'file' => 'b.rb' },
      { 'type' => 'loop', 'cops' => %w[Style/C],
        'signature' => 'loop:Style/C', 'file' => 'c.rb' },
      { 'type' => 'broken_autocorrect', 'cops' => %w[Style/D],
        'signature' => 'syntax:boom', 'file' => 'd.rb' }
    ]
  end

  let(:known_yaml) do
    <<~YAML
      - pr: 100
        status: open
        note: A vs B loop
        signatures:
          - 'loop:Style/A+Style/B'
      - pr: 200
        status: merged
        note: boom fix
        signature_regex: 'syntax:boom'
    YAML
  end

  def triage
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'known_issues.yml')
      File.write(path, known_yaml)
      return described_class.new(findings, known_path: path)
    end
  end

  it 'splits findings into new, known, and regression buckets' do
    buckets = triage.buckets

    expect(buckets[:new].map { |g| g[:signature] }).to eq(['loop:Style/C'])
    expect(buckets[:known].map { |g| g[:signature] }).to eq(['loop:Style/A+Style/B'])
    expect(buckets[:regression].map { |g| g[:signature] }).to eq(['syntax:boom'])
  end

  it 'counts distinct files per group' do
    group = triage.buckets[:known].first

    expect(group[:count]).to eq(2)
    expect(group[:files]).to contain_exactly('a.rb', 'b.rb')
  end

  it 'renders all sections in the body' do
    body = triage.body

    expect(body).to include('1 new, 1 regression(s), 1 known with open PRs')
    expect(body).to include('## New')
    expect(body).to include('## Regressions')
    expect(body).to include('rubocop/pull/100')
    expect(body).to include('rubocop/pull/200')
  end

  it 'treats everything as new without a known file' do
    triage = described_class.new(findings, known_path: nil)

    expect(triage.buckets[:new].size).to eq(3)
  end
end
