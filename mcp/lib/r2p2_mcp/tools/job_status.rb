# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `job_status`: reports the state of a background job.
    class JobStatus < MCP::Tool
      extend Helpers

      description 'Status of a background job (default: the latest) without waiting. Includes extracted error ' \
                  'lines when it failed. To wait for a running job use job_wait.'
      input_schema(properties: { job_id: { type: 'integer' } })
      annotations(read_only_hint: true)

      class << self
        def call(job_id: nil)
          job = JobManager.find(job_id) or return text('no such job', error: true)
          text(job_report(job))
        end
      end
    end
  end
end
