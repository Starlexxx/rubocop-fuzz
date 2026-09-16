# frozen_string_literal: true

require 'tempfile'

module RuboCopFuzz
  # Runs the RuboCop checkout under test as a subprocess with a hard timeout.
  # The child gets its own process group so a hung run can be killed with
  # everything it spawned. A timeout comes back as a result status, not an
  # exception: the harness treats it as a finding.
  class Invoker
    Result = Struct.new(:status, :exitstatus, :stdout, :stderr, :duration, keyword_init: true) do
      def timeout? = status == :timeout
    end

    POLL_INTERVAL = 0.1
    MEMORY_LIMIT_BYTES = 3 * 1024 * 1024 * 1024

    def initialize(rubocop_dir:, timeout:)
      @rubocop_dir = rubocop_dir
      @timeout = timeout
    end

    def run(args, chdir:)
      out_f = Tempfile.create('fuzz-out')
      err_f = Tempfile.create('fuzz-err')
      started = monotonic
      env = { 'BUNDLE_GEMFILE' => File.join(@rubocop_dir, 'Gemfile'),
              'PARALLEL_PROCESSOR_COUNT' => '1' }
      spawn_opts = { chdir: chdir, pgroup: true, out: out_f.path, err: err_f.path }
      spawn_opts[:rlimit_as] = MEMORY_LIMIT_BYTES if RUBY_PLATFORM.include?('linux')
      pid = Process.spawn(env, 'bundle', 'exec', 'rubocop', *args, **spawn_opts)
      status = wait_with_deadline(pid, started)
      Result.new(
        status: status.nil? ? :timeout : :done,
        exitstatus: status&.exitstatus,
        stdout: File.read(out_f.path),
        stderr: File.read(err_f.path),
        duration: monotonic - started
      )
    ensure
      [out_f, err_f].each { |f| File.unlink(f.path) rescue nil }
    end

    private

    # Returns Process::Status, or nil on timeout (after killing the pgroup).
    def wait_with_deadline(pid, started)
      deadline = started + @timeout
      loop do
        _, status = Process.wait2(pid, Process::WNOHANG)
        return status if status

        if monotonic > deadline
          begin
            Process.kill(:KILL, -pid)
          rescue Errno::ESRCH, Errno::EPERM
            nil
          end
          Process.wait2(pid)
          return nil
        end
        sleep POLL_INTERVAL
      end
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
