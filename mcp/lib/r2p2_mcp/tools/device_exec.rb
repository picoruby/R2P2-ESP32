# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `device_exec`: runs a shell command on the connected device.
    class DeviceExec < MCP::Tool
      extend Helpers

      description 'Run a shell command on the device (e.g. `ls`, `cat hello.rb`, `./app.rb`) and return its output ' \
                  'once the prompt returns. ' \
                  'On timeout the command is interrupted (Ctrl-C, then Ctrl-D) and the partial output is returned.'
      input_schema(
        properties: {
          command: { type: 'string' },
          timeout: { type: 'number', description: 'seconds, default 10' }
        },
        required: ['command']
      )

      class << self
        def call(command:, timeout: 10)
          device_call do
            lines, status = Device.exec(command, timeout: timeout)
            out = lines.join("\n")
            out += "\n[timeout after #{timeout}s; interrupted, back at the prompt]" if status == :timeout
            if status == :stuck
              out += "\n[timeout after #{timeout}s; could not get back to the prompt, try device_reset]"
            end
            text(out, error: status != :ok)
          end
        end
      end
    end
  end
end
