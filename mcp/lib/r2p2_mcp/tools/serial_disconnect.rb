# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `serial_disconnect`: closes the connection and releases the port.
    class SerialDisconnect < MCP::Tool
      extend Helpers

      description 'Close the connection and release the port.'

      class << self
        def call
          target = Device.target
          Device.disconnect
          text(target ? "disconnected from #{target}" : 'not connected')
        end
      end
    end
  end
end
