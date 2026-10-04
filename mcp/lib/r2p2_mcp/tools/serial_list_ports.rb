# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `serial_list_ports`: lists serial ports that look like ESP32 boards.
    class SerialListPorts < MCP::Tool
      extend Helpers

      PATTERNS = %w[/dev/ttyACM* /dev/ttyUSB* /dev/cu.usbmodem* /dev/cu.usbserial* /dev/cu.SLAB*
                    /dev/cu.wchusbserial*].freeze

      description 'List serial ports that look like ESP32 boards.'
      annotations(read_only_hint: true)

      class << self
        def call
          by_id = Dir['/dev/serial/by-id/*'].to_h { |link| [File.realpath(link), File.basename(link)] }
          lines = Dir[*PATTERNS].sort.map { |path| describe(path, by_id) }
          current = Device.target
          lines << '' << "connected: #{current}" if current
          text(lines.empty? ? 'no serial ports found' : lines.join("\n"))
        end

        private

        def describe(path, by_id)
          name = by_id[File.realpath(path)]
          name ? "#{path}  (#{name})" : path
        end
      end
    end
  end
end
