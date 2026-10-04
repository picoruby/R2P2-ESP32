# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `job_wait`: waits for a running background job.
    class JobWait < MCP::Tool
      extend Helpers

      description 'Wait for a background job (default: the latest) to finish, up to timeout seconds, then report ' \
                  'it. Use it after setup / build / flash returned "still running".'
      input_schema(
        properties: {
          job_id: { type: 'integer' },
          timeout: { type: 'number', description: "seconds, default #{DEFAULT_WAIT}" }
        }
      )
      annotations(read_only_hint: true)

      class << self
        def call(job_id: nil, timeout: DEFAULT_WAIT)
          job = JobManager.find(job_id) or return text('no such job', error: true)
          finished = JobManager.finished_within?(job, timeout)
          report = job_report(job)
          report += "\nStill running after #{timeout}s. Call job_wait again." unless finished
          text(report, error: finished && job.status == 'failed')
        end
      end
    end
  end
end
