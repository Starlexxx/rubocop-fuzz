# frozen_string_literal: true

require 'json'
require 'fileutils'

module RuboCopFuzz
  # Writes findings as JSONL plus a markdown report deduped by
  # (type, cop set, error signature).
  class Report
    def initialize(findings, out_dir:, rubocop_dir:)
      @findings = findings.map { |f| stringify(f) }
      @out_dir = out_dir
      @rubocop_dir = rubocop_dir
    end

    def write
      FileUtils.mkdir_p(@out_dir)
      File.write(File.join(@out_dir, 'findings.jsonl'),
                 @findings.map { |f| JSON.generate(f) }.join("\n") + "\n")
      File.write(File.join(@out_dir, 'report.md'), markdown)
      [File.join(@out_dir, 'findings.jsonl'), File.join(@out_dir, 'report.md')]
    end

    def groups
      @findings.group_by { |f| [f['type'], f['cops'].sort, f['signature']] }
    end

    private

    def stringify(finding)
      JSON.parse(JSON.generate(finding))
    end

    def markdown
      lines = ["# rubocop-fuzz findings", '',
               "RuboCop under test: `#{@rubocop_dir}` (#{git_rev})", '',
               "Total findings: #{@findings.size}, unique: #{groups.size}", '']
      groups.each_with_index do |((type, cops, signature), items), i|
        sample = items.first
        lines << "## #{i + 1}. [#{type}] #{cops.join(', ')}"
        lines << ''
        lines << "- signature: `#{signature}`"
        lines << "- occurrences: #{items.size}"
        lines << "- sample file: `#{sample['file']}`" if sample['file']
        lines << "- config: `#{sample['config']}`"
        lines << "- shards: #{items.map { |f| f['shard'] }.uniq.take(5).join(', ')}"
        lines << ''
      end
      lines.join("\n")
    end

    def git_rev
      Dir.chdir(@rubocop_dir) { `git rev-parse --short HEAD`.strip }
    rescue StandardError
      'unknown'
    end
  end
end
