# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `device_exec`: runs a shell command on the connected device.
    class DeviceExec < MCP::Tool
      extend Helpers

      description 'Run a shell command on the device (e.g. `ls`, `cat hello.rb`, `./app.rb`) and return its output ' \
                  'once the prompt returns. ' \
                  'On timeout the command is interrupted (Ctrl-C, then Ctrl-D) and the partial output is returned; ' \
                  'if the shell never took the command (device booting or hung) nothing is sent and you are told so.'
      input_schema(
        properties: {
          command: { type: 'string' },
          timeout: { type: 'number', description: 'seconds, default 10' }
        },
        required: ['command']
      )

      EXEC_NOTES = {
        timeout: "\n[timeout after %<timeout>ss; interrupted, back at the prompt]",
        stuck: "\n[timeout after %<timeout>ss; could not get back to the prompt, try device_reset]",
        unresponsive: "\n[no response within %<timeout>ss: the shell did not take the command (device booting, " \
                      'crashed or hung?). Nothing was sent. Boot can take up to a minute: wait and check device_log; ' \
                      'device_reset if it stays silent]'
      }.freeze

      class << self
        def call(command:, timeout: 10)
          device_call do
            lines, status = Device.exec(command, timeout: timeout)
            text(format(lines.join("\n") + EXEC_NOTES[status].to_s, timeout: timeout), error: status != :ok)
          end
        end
      end
    end
  end
end
