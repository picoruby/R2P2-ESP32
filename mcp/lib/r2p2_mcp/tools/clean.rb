# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `clean`: cleans build artifacts.
    class Clean < MCP::Tool
      extend Helpers

      description 'Clean build artifacts (rake clean, or deep_clean). Docker by default. Waits for it to finish ' \
                  '(see timeout).'
      input_schema(
        properties: {
          deep: { type: 'boolean', description: 'deep_clean (also removes the ESP32 build repos)' },
          native: { type: 'boolean' },
          timeout: WAIT_PROPERTY
        }
      )

      class << self
        def call(deep: false, native: false, timeout: DEFAULT_WAIT)
          task = deep ? 'deep_clean' : 'clean'
          run_job(label: task, command: RakeTask.command(task, native: native), timeout: timeout)
        end
      end
    end
  end
end
