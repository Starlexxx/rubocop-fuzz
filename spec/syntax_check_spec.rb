# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RuboCopFuzz::SyntaxCheck do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.write(path, content)
    path
  end

  it 'reports files with syntax errors' do
    good = write('good.rb', "x = 1\n")
    bad = write('bad.rb', "def foo(\n")

    result = described_class.broken_files([good, bad])
    expect(result.size).to eq(1)
    expect(result.first[:file]).to eq(bad)
    expect(result.first[:error]).not_to be_empty
  end

  it 'returns an empty list for valid files' do
    expect(described_class.broken_files([write('a.rb', "x = 1\n")])).to eq([])
  end

  it 'returns an empty list for no files' do
    expect(described_class.broken_files([])).to eq([])
  end
end
