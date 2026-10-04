# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

module R2p2Mcp
  # Runs one external command at a time in the background, logging to a file.
  module JobManager
    Job = Struct.new(:id, :label, :command, :log_path, :started_at, :finished_at, :exit_code, keyword_init: true) do
      def running? = finished_at.nil?

      def status
        return 'running' if running?

        exit_code.zero? ? 'succeeded' : 'failed'
      end

      def elapsed
        ((finished_at || Time.now) - started_at).round(1)
      end
    end

    ERROR_PATTERN = /error|undefined reference|fatal|\bFAILED\b|\bAborting\b|not found|No such file/i

    @jobs = []
    @mutex = Mutex.new
    @log_dir = Dir.mktmpdir('r2p2-mcp-')
    at_exit { FileUtils.rm_rf(@log_dir) }

    class << self
      def start(label:, command:, env: {}, on_finish: nil)
        @mutex.synchronize do
          running = @jobs.find(&:running?)
          raise "job ##{running.id} (#{running.label}) is still running" if running

          job = new_job(label, command)
          watch(job, spawn_job(job, env), on_finish)
          @jobs << job
          job
        end
      end

      # Waits up to +timeout+ seconds for the job to finish; returns whether it did.
      def finished_within?(job, timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        sleep 0.2 while job.running? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        !job.running?
      end

      def find(job_id = nil)
        job_id ? @jobs.find { |job| job.id == job_id } : @jobs.last
      end

      def log_lines(job)
        File.exist?(job.log_path) ? File.read(job.log_path, mode: 'rb').scrub.lines : []
      end

      def tail(job, count)
        log_lines(job).last(count).join
      end

      def errors(job, max: 30)
        log_lines(job).grep(ERROR_PATTERN).last(max).map(&:chomp)
      end

      private

      def new_job(label, command)
        id = @jobs.size + 1
        Job.new(id: id, label: label, command: command, log_path: File.join(@log_dir, "job-#{id}.log"),
                started_at: Time.now)
      end

      def spawn_job(job, env)
        # Don't leak this server's own Bundler environment (mcp/Gemfile) into rake.
        Bundler.with_unbundled_env do
          Process.spawn(env, *job.command, chdir: ROOT, in: File::NULL, out: job.log_path, err: %i[child out],
                                           pgroup: true)
        end
      end

      def watch(job, pid, on_finish)
        Thread.new do
          _, status = Process.wait2(pid)
          job.exit_code = status.exitstatus || -status.termsig
          on_finish&.call(job) # the job counts as running until this (e.g. reconnecting after flash) is done
          job.finished_at = Time.now
        end
      end
    end
  end
end
