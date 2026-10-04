# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `job_status`: reports the state of a background job.
    class JobStatus < MCP::Tool
      extend Helpers

      description 'Status of a background job (default: the latest). Includes extracted error lines when it failed.'
      input_schema(properties: { job_id: { type: 'integer' } })
      annotations(read_only_hint: true)

      class << self
        def call(job_id: nil)
          job = JobManager.find(job_id) or return text('no such job', error: true)
          text((summary(job) + details(job)).join("\n"))
        end

        private

        def summary(job)
          lines = ["job ##{job.id} #{job.label}: #{job.status} (#{job.elapsed}s)"]
          lines << "exit code: #{job.exit_code}" unless job.running?
          lines
        end

        def details(job)
          if job.status == 'failed'
            ['--- error lines ---', *JobManager.errors(job), '--- last 20 lines ---', JobManager.tail(job, 20)]
          elsif job.running?
            ['--- last 5 lines ---', JobManager.tail(job, 5)]
          else
            []
          end
        end
      end
    end
  end
end
