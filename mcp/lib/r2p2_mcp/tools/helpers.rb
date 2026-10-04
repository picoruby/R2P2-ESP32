# frozen_string_literal: true

module R2p2Mcp
  module Tools
    DEFAULT_WAIT = 300 # seconds a job tool waits for the job to finish

    WAIT_PROPERTY = {
      type: 'number',
      description: "seconds to wait for it to finish (default #{DEFAULT_WAIT}; 0 = return at once). If it takes " \
                   'longer it keeps running; call job_wait'
    }.freeze

    # Shared response and error-handling helpers for the tools (`extend`ed into each).
    module Helpers
      def text(message, error: false)
        MCP::Tool::Response.new([{ type: 'text', text: message }], error: error)
      end

      # Starts a background job and waits for it up to +timeout+ seconds. Returns the final report, or, when
      # it is still running by then, a note to call job_wait (the job keeps running).
      def run_job(label:, command:, env: {}, on_finish: nil, timeout: DEFAULT_WAIT)
        job = JobManager.start(label: label, command: command, env: env, on_finish: on_finish)
        return text("Started job ##{job.id} (#{job.label}). Call job_wait or job_status.") unless timeout.positive?

        finished = JobManager.finished_within?(job, timeout)
        report = job_report(job)
        report += "\nStill running after #{timeout}s; it keeps going. Call job_wait (job_id #{job.id})." unless finished
        text(report, error: finished && job.status == 'failed')
      rescue StandardError => e
        text(e.message, error: true)
      end

      def job_report(job)
        lines = ["job ##{job.id} #{job.label}: #{job.status} (#{job.elapsed}s)"]
        lines << "exit code: #{job.exit_code}" unless job.running?
        (lines + job_details(job)).join("\n")
      end

      # Device errors (not connected, I/O failure) become MCP error responses.
      def device_call
        yield
      rescue Device::NotConnected, IOError, SystemCallError => e
        text(e.message, error: true)
      end

      private

      def job_details(job)
        case job.status
        when 'failed'
          ['--- error lines ---', *JobManager.errors(job), '--- last 20 lines ---', JobManager.tail(job, 20)]
        when 'running' then ['--- last 5 lines ---', JobManager.tail(job, 5)]
        else ['--- last 3 lines ---', JobManager.tail(job, 3)]
        end
      end
    end
  end
end
