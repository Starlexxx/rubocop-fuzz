# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RuboCopFuzz::Gemfile do
  around do |example|
    Dir.mktmpdir do |dir|
      @rubocop_dir = dir
      File.write(File.join(dir, 'Gemfile'), "gemspec\n")
      example.run
    end
  end

  it 'uses the checkout Gemfile when there are no plugins' do
    gemfile = described_class.new(rubocop_dir: @rubocop_dir)
    expect(gemfile.path).to eq(File.join(@rubocop_dir, 'Gemfile'))
  end

  it 'points bundler at every checkout by path' do
    gemfile = described_class.new(rubocop_dir: @rubocop_dir,
                                  plugins: { 'rubocop-performance' => '/x/perf', 'rubocop-rails' => '/x/rails' })
    expect(gemfile.source).to eq(<<~RUBY)
      source 'https://rubygems.org'
      gem 'rubocop', path: '#{@rubocop_dir}'
      gem 'rubocop-performance', path: '/x/perf'
      gem 'rubocop-rails', path: '/x/rails'
    RUBY
  end
end
