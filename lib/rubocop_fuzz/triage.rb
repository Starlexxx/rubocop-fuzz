# frozen_string_literal: true

require 'json'
require 'yaml'

module RuboCopFuzz
  # Partitions grouped findings into new / regression / known-open buckets
  # using known_issues.yml and renders the nightly issue body.
  class Triage
    Entry = Struct.new(:pr, :status, :note, :signatures, :signature_regex, keyword_init: true)

    def initialize(findings, known_path:)
      @findings = findings
      @entries = load_entries(known_path)
    end

    def buckets
      @buckets ||= begin
        result = { new: [], regression: [], known: [] }
        grouped.each do |group|
          entry = match_entry(group[:signature])
          if entry.nil?
            result[:new] << group
          elsif entry.status == 'merged'
            result[:regression] << group.merge(entry: entry)
          else
            result[:known] << group.merge(entry: entry)
          end
        end
        result
      end
    end

    def body
      new_groups = buckets[:new]
      regressions = buckets[:regression]
      known = buckets[:known]

      lines = ["Nightly fuzz run: #{@findings.size} finding(s), #{grouped.size} unique group(s): " \
               "#{new_groups.size} new, #{regressions.size} regression(s), " \
               "#{known.size} known with open PRs.", '']
      lines.concat(section('New', new_groups))
      lines.concat(section('Regressions (signature reappeared after a merged fix)', regressions))
      lines.concat(known_section(known))
      lines.join("\n")
    end

    def grouped
      @grouped ||= @findings
                   .group_by { |f| [f['type'], f['cops'].sort, f['signature']] }
                   .map do |(type, cops, signature), items|
                     { type: type, cops: cops, signature: signature, count: items.size,
                       files: items.map { |f| f['file'] }.compact.uniq,
                       sample: items.first }
                   end
                   .sort_by { |g| [-g[:files].size, -g[:count]] }
    end

    private

    def load_entries(path)
      return [] unless path && File.exist?(path)

      YAML.safe_load_file(path).to_a.map do |raw|
        Entry.new(pr: raw['pr'], status: raw['status'], note: raw['note'],
                  signatures: raw['signatures'] || [],
                  signature_regex: raw['signature_regex'] && Regexp.new(raw['signature_regex']))
      end
    end

    def match_entry(signature)
      @entries.find do |entry|
        entry.signatures.include?(signature) || entry.signature_regex&.match?(signature)
      end
    end

    def section(title, groups)
      return [] if groups.empty?

      lines = ["## #{title}", '', '| files | hits | type | signature |', '|---|---|---|---|']
      groups.first(30).each do |g|
        pr = g[:entry] ? " ([##{g[:entry].pr}](https://github.com/rubocop/rubocop/pull/#{g[:entry].pr}))" : ''
        lines << "| #{g[:files].size} | #{g[:count]} | #{g[:type]} | `#{truncate(g[:signature])}`#{pr} |"
      end
      lines << "… #{groups.size - 30} more group(s) omitted" if groups.size > 30
      lines << ''
      lines
    end

    def known_section(groups)
      return [] if groups.empty?

      lines = ['<details><summary>Known findings with open PRs ' \
               "(#{groups.sum { |g| g[:count] }} finding(s) in #{groups.size} group(s))</summary>", '']
      groups.group_by { |g| g[:entry].pr }.each do |pr, prs_groups|
        hits = prs_groups.sum { |g| g[:count] }
        note = prs_groups.first[:entry].note
        lines << "- [##{pr}](https://github.com/rubocop/rubocop/pull/#{pr}) — #{note}: " \
                 "#{prs_groups.size} group(s), #{hits} finding(s)"
      end
      lines << ''
      lines << '</details>'
      lines
    end

    def truncate(signature)
      signature.length > 90 ? "#{signature[0, 90]}…" : signature
    end
  end
end
