# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `job_log`: tails the log of a background job.
    class JobLog < MCP::Tool
      extend Helpers

      description 'Tail the log of a background job (default: the latest).'
      input_schema(properties: { job_id: { type: 'integer' }, lines: { type: 'integer', description: 'default 100' } })
      annotations(read_only_hint: true)

      class << self
        def call(job_id: nil, lines: 100)
          job = JobManager.find(job_id) or return text('no such job', error: true)
          text(JobManager.tail(job, lines))
        end
      end
    end
  end
end
