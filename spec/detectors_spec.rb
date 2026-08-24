# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RuboCopFuzz::Detectors do
  describe '.scan_stderr' do
    it 'detects a cop crash' do
      stderr = <<~ERR
        An error occurred while Layout/ArgumentAlignment cop was inspecting /tmp/x/foo.rb:10:4.
        To see the complete backtrace run rubocop -d.
      ERR

      findings = described_class.scan_stderr(stderr)
      expect(findings).to eq([
        { type: 'crash', cops: ['Layout/ArgumentAlignment'], location: '/tmp/x/foo.rb:10:4' }
      ])
    end

    it 'detects an infinite correction loop with a cop chain' do
      stderr = <<~ERR
        Infinite loop detected in /tmp/x/foo.rb and caused by Layout/ArgumentAlignment -> Layout/FirstMethodArgumentLineBreak
        /path/lib/rubocop/runner.rb:346:in 'block in iterate_until_no_changes'
      ERR

      findings = described_class.scan_stderr(stderr)
      expect(findings.size).to eq(1)
      expect(findings.first[:type]).to eq('loop')
      expect(findings.first[:cops]).to contain_exactly(
        'Layout/ArgumentAlignment', 'Layout/FirstMethodArgumentLineBreak'
      )
      expect(findings.first[:location]).to eq('/tmp/x/foo.rb')
    end

    it 'detects a loop without a cause chain' do
      findings = described_class.scan_stderr("Infinite loop detected in /tmp/x/foo.rb\n")
      expect(findings.first[:type]).to eq('loop')
      expect(findings.first[:cops]).to eq([])
    end

    it 'splits comma-separated cops inside a loop chain' do
      stderr = "Infinite loop detected in /t/a.rb and caused by Style/A, Style/B -> Style/A\n"
      findings = described_class.scan_stderr(stderr)
      expect(findings.first[:cops]).to contain_exactly('Style/A', 'Style/B')
    end

    it 'returns no findings for clean output' do
      expect(described_class.scan_stderr("Inspecting 3 files\n...\n")).to eq([])
    end
  end

  describe '.corrected_offenses' do
    it 'extracts corrected offenses from json output' do
      json = {
        files: [
          { path: 'a.rb', offenses: [
            { cop_name: 'Style/A', corrected: true },
            { cop_name: 'Style/B', corrected: false }
          ] },
          { path: 'b.rb', offenses: [{ cop_name: 'Style/A', corrected: true }] }
        ]
      }.to_json

      expect(described_class.corrected_offenses(json)).to eq([
        { cop: 'Style/A', file: 'a.rb' },
        { cop: 'Style/A', file: 'b.rb' }
      ])
    end

    it 'returns an empty list for unparseable output' do
      expect(described_class.corrected_offenses('boom')).to eq([])
    end
  end

  describe '.crash_signature' do
    it 'extracts error class and normalized message from debug output' do
      out = <<~OUT
        Inspecting 1 file
        /tmp/repro/foo.rb:12:in 'block': undefined method 'source' for nil (NoMethodError)
        \tfrom /path/lib/rubocop/cop/layout/foo.rb:88:in 'on_send'
      OUT

      sig = described_class.crash_signature('Layout/Foo', out)
      expect(sig).to eq("Layout/Foo: NoMethodError: undefined method 'source' for nil")
    end

    it 'normalizes paths and numbers inside messages' do
      out = "/a/b.rb:1:in 'x': failed on /tmp/xyz/file.rb at line 42 (RuntimeError)\n"
      sig = described_class.crash_signature('Style/X', out)
      expect(sig).to eq('Style/X: RuntimeError: failed on <path> at line N')
    end

    it 'falls back when no error line is present' do
      expect(described_class.crash_signature('Style/X', "nothing here\n"))
        .to eq('unreproduced:Style/X')
    end
  end
end
