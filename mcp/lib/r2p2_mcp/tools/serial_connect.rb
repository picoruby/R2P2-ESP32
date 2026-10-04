# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `serial_connect`: opens the connection to a device (serial or tcp://).
    class SerialConnect < MCP::Tool
      extend Helpers

      description "Connect to a device's picoruby-shell and keep the port open (replaces any previous connection). " \
                  'port is a serial device (/dev/ttyACM0) or tcp://host:port (e.g. QEMU). ' \
                  'Release it with serial_disconnect when you need the port for something else (rake monitor, a web ' \
                  'terminal).'
      input_schema(
        properties: {
          port: { type: 'string', description: 'e.g. /dev/ttyACM0 or tcp://127.0.0.1:5555' },
          baud: { type: 'integer', description: 'serial only; default 115200' }
        },
        required: ['port']
      )

      class << self
        def call(port:, baud: Port::DEFAULT_BAUD)
          prompt = Device.connect(port, baud: baud)
          if prompt
            text("connected to #{port}; shell prompt seen")
          else
            text("connected to #{port}, but no shell prompt within 3s (device " \
                 'booting, crashed, or not at the prompt). Check device_log.')
          end
        rescue ArgumentError, IOError, SystemCallError => e
          text("cannot open #{port}: #{e.message}", error: true)
        end
      end
    end
  end
end
