# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RuboCopFuzz::Snippets do
  around do |example|
    Dir.mktmpdir do |dir|
      @spec_dir = dir
      example.run
    end
  end

  def write_spec(content)
    File.write(File.join(@spec_dir, 'foo_spec.rb'), content)
  end

  it 'extracts heredoc sources without offense annotations' do
    write_spec(<<~'SPEC')
      it 'registers an offense' do
        expect_offense(<<~RUBY)
          foo(bar)
          ^^^^^^^^ Message.
        RUBY

        expect_correction(<<~RUBY)
          foo bar
        RUBY
      end
    SPEC

    expect(described_class.new([@spec_dir]).sources).to contain_exactly("foo(bar)\n", "foo bar\n")
  end

  it 'skips heredocs with interpolation, placeholders or invalid syntax' do
    write_spec(<<~'SPEC')
      expect_offense(<<~RUBY)
        foo(#{arg})
      RUBY
      expect_offense(<<~RUBY, name: 'x')
        %{name} = 1
        ^{name} Message.
      RUBY
      expect_no_offenses(<<~RUBY)
        def foo(
      RUBY
    SPEC

    expect(described_class.new([@spec_dir]).sources).to be_empty
  end

  it 'removes duplicates across specs' do
    write_spec(<<~'SPEC')
      expect_no_offenses(<<~RUBY)
        foo
      RUBY
      expect_no_offenses(<<~RUBY)
        foo
      RUBY
    SPEC

    expect(described_class.new([@spec_dir]).sources).to eq(["foo\n"])
  end

  it 'adds wrapped copies that are valid Ruby' do
    write_spec(<<~'SPEC')
      expect_no_offenses(<<~RUBY)
        bar(1)
      RUBY
    SPEC

    sources = described_class.new([@spec_dir], wrappers: 3, seed: 1).sources
    expect(sources.size).to eq(4)
    expect(sources.first).to eq("bar(1)\n")
    expect(sources.drop(1)).to all(include('bar(1)'))
    expect(sources).to all(satisfy { |s| Prism.parse(s).success? })
  end

  it 'picks the same wrappers for the same seed' do
    write_spec(<<~'SPEC')
      expect_no_offenses(<<~RUBY)
        bar(1)
      RUBY
    SPEC

    first = described_class.new([@spec_dir], wrappers: 2, seed: 7).sources
    second = described_class.new([@spec_dir], wrappers: 2, seed: 7).sources
    expect(first).to eq(second)
  end

  it 'writes one file per source' do
    write_spec(<<~'SPEC')
      expect_no_offenses(<<~RUBY)
        foo
      RUBY
    SPEC

    Dir.mktmpdir do |out|
      expect(described_class.new([@spec_dir]).write(out)).to eq(1)
      expect(Dir.children(out).map { |f| File.read(File.join(out, f)) }).to eq(["foo\n"])
    end
  end
end
