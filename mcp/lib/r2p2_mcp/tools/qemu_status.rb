# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `qemu_status`: whether QEMU is running, with the tail of its build / boot log.
    class QemuStatus < MCP::Tool
      extend Helpers

      description 'Whether QEMU is running, and the tail of its rake / build output (useful while it is ' \
                  'still building).'
      input_schema(properties: { lines: { type: 'integer', description: 'default 20' } })
      annotations(read_only_hint: true)

      class << self
        def call(lines: 20)
          state = if Qemu.ready? then 'running (UART ready)'
                  elsif Qemu.running? then 'starting (building)'
                  else 'not running'
                  end
          text("QEMU: #{state}\n#{Qemu.log.lines.last(lines).join}")
        end
      end
    end
  end
end
