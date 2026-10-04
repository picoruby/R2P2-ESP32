# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # Shared response and error-handling helpers for the tools (`extend`ed into each).
    module Helpers
      def text(message, error: false)
        MCP::Tool::Response.new([{ type: 'text', text: message }], error: error)
      end

      def started(job)
        text("Started job ##{job.id} (#{job.label}). Poll with job_status / job_log.\n$ #{job.command.join(' ')}")
      end

      def start_job(label:, command:, env: {}, on_finish: nil)
        started(JobManager.start(label: label, command: command, env: env, on_finish: on_finish))
      rescue StandardError => e
        text(e.message, error: true)
      end

      # Device errors (not connected, I/O failure) become MCP error responses.
      def device_call
        yield
      rescue Device::NotConnected, IOError, SystemCallError => e
        text(e.message, error: true)
      end
    end
  end
end
