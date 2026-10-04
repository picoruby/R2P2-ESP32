# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `device_reset`: reboots the device and returns the boot log.
    class DeviceReset < MCP::Tool
      extend Helpers

      description 'Reboot the device (shell `reboot`) and return the boot log up to the next prompt.'
      input_schema(properties: { timeout: { type: 'number', description: 'seconds, default 30' } })

      class << self
        def call(timeout: 30)
          device_call do
            lines, ok = Device.reset(timeout: timeout)
            text(lines.join("\n") + (ok ? '' : "\n[no prompt within #{timeout}s]"), error: !ok)
          end
        end
      end
    end
  end
end
