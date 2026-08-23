# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RuboCopFuzz::Corpus do
  around do |example|
    Dir.mktmpdir do |dir|
      @gems_dir = dir
      example.run
    end
  end

  def make_gem(name, files)
    root = File.join(@gems_dir, name)
    files.each do |rel, content|
      path = File.join(root, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
    root
  end

  it 'keeps only the latest version of each gem' do
    make_gem('foo-1.0.0', 'lib/foo.rb' => 'x = 1')
    make_gem('foo-1.10.0', 'lib/foo.rb' => 'x = 2')
    make_gem('foo-1.9.0', 'lib/foo.rb' => 'x = 3')

    shards = described_class.new(@gems_dir).shards
    expect(shards.map(&:name)).to eq(['foo'])
    expect(shards.first.root).to end_with('foo-1.10.0')
  end

  it 'compares versions numerically, not lexically' do
    make_gem('bar-9.0.0', 'lib/bar.rb' => 'x = 1')
    make_gem('bar-10.0.0', 'lib/bar.rb' => 'x = 2')

    shards = described_class.new(@gems_dir).shards
    expect(shards.first.root).to end_with('bar-10.0.0')
  end

  it 'splits large gems into multiple shards' do
    files = (1..5).to_h { |i| ["lib/f#{i}.rb", "x = #{i}"] }
    make_gem('big-1.0.0', files)

    shards = described_class.new(@gems_dir, max_files_per_shard: 2).shards
    expect(shards.map(&:name)).to eq(['big.0', 'big.1', 'big.2'])
    expect(shards.flat_map(&:files).size).to eq(5)
  end

  it 'skips empty and oversized files' do
    make_gem('sz-1.0.0',
             'lib/empty.rb' => '',
             'lib/big.rb' => 'a' * (described_class::MAX_FILE_BYTES + 1),
             'lib/ok.rb' => 'x = 1')

    shards = described_class.new(@gems_dir).shards
    expect(shards.first.relative_files).to eq(['lib/ok.rb'])
  end

  it 'exposes shard files relative to the gem root' do
    make_gem('rel-1.0.0', 'lib/a/b.rb' => 'x = 1')

    shard = described_class.new(@gems_dir).shards.first
    expect(shard.relative_files).to eq(['lib/a/b.rb'])
  end
end
