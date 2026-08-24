# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RuboCopFuzz::DependencyMiner do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def write_cop(department, name, content)
    path = File.join(@dir, 'lib', 'rubocop', 'cop', department, "#{name}.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  it 'builds a cluster from cross-cop config references' do
    write_cop('layout', 'first_argument_indentation', <<~RUBY)
      config.for_enabled_cop('Layout/ArgumentAlignment')
      config.cop_enabled?('Layout/FirstMethodArgumentLineBreak')
    RUBY
    write_cop('layout', 'plain', 'no references here')

    expect(described_class.new(@dir).clusters).to eq([
      %w[Layout/FirstArgumentIndentation Layout/ArgumentAlignment Layout/FirstMethodArgumentLineBreak]
    ])
  end

  it 'deduplicates repeated references' do
    write_cop('style', 'foo', <<~RUBY)
      config.for_cop('Style/Bar')
      config.for_cop('Style/Bar')
    RUBY

    expect(described_class.new(@dir).clusters).to eq([%w[Style/Foo Style/Bar]])
  end
end
