# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'fileutils'

module RuboCopFuzz
  # Forks a child per job; a crashing job can't take the harness down.
  class Pool
    def initialize(size:)
      @size = size
    end

    def run(jobs, progress: nil)
      results_dir = Dir.mktmpdir('rubocop-fuzz-results')
      results = Array.new(jobs.size)
      queue = jobs.each_with_index.to_a
      active = {}

      until queue.empty? && active.empty?
        while active.size < @size && !queue.empty?
          job, idx = queue.shift
          active[spawn_child(job, idx, results_dir) { |j| yield j }] = idx
        end

        pid, status = Process.wait2
        idx = active.delete(pid)
        next if idx.nil?

        results[idx] = read_result(results_dir, idx, status)
        progress&.call(idx, results[idx])
      end

      results
    ensure
      FileUtils.remove_entry(results_dir) if results_dir
    end

    private

    def spawn_child(job, idx, results_dir)
      fork do
        result = yield(job)
        File.write(File.join(results_dir, "#{idx}.json"), JSON.generate(result))
        exit!(0)
      end
    end

    def read_result(results_dir, idx, status)
      path = File.join(results_dir, "#{idx}.json")
      return { 'error' => "worker died: #{status}" } unless File.exist?(path)

      JSON.parse(File.read(path))
    end
  end
end
