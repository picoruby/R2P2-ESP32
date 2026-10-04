# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `qemu_stop`: stops the QEMU instance and closes its connection.
    class QemuStop < MCP::Tool
      extend Helpers

      description 'Stop the QEMU instance started by qemu_start (its /home is discarded).'

      class << self
        def call
          Device.disconnect if Device.target == Qemu::TARGET
          return text('QEMU is not running') unless Qemu.running?

          Qemu.stop
          text('QEMU stopped')
        end
      end
    end
  end
end
