# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `clean`: cleans build artifacts as a background job.
    class Clean < MCP::Tool
      extend Helpers

      description 'Clean build artifacts (rake clean, or deep_clean). Background job, Docker by default.'
      input_schema(
        properties: {
          deep: { type: 'boolean', description: 'deep_clean (also removes the ESP32 build repos)' },
          native: { type: 'boolean' }
        }
      )

      class << self
        def call(deep: false, native: false)
          task = deep ? 'deep_clean' : 'clean'
          start_job(label: task, command: RakeTask.command(task, native: native))
        end
      end
    end
  end
end
