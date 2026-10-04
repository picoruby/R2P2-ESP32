# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `device_reset`: reboots the device and returns the boot log.
    class DeviceReset < MCP::Tool
      extend Helpers

      description 'Reboot the device (shell `reboot`) and return the boot log up to the next prompt. If the shell ' \
                  'does not come back, a serial device is reset through DTR/RTS (like esptool). Boot can take up to ' \
                  'a minute on some builds.'
      input_schema(properties: { timeout: { type: 'number', description: 'seconds, default 60' } })

      class << self
        def call(timeout: 60)
          device_call do
            lines, ok, method = Device.reset(timeout: timeout)
            text("[reset via #{method}]\n#{lines.join("\n")}#{"\n[no prompt within #{timeout}s]" unless ok}",
                 error: !ok)
          end
        end
      end
    end
  end
end
