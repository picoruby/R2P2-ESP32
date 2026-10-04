# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `device_log`: tails what the connected device has printed.
    class DeviceLog < MCP::Tool
      extend Helpers

      description 'Tail everything the device has printed since connecting (last 256 KiB kept), rendered as plain ' \
                  'text. ' \
                  'Panic / crash lines (Guru Meditation, Backtrace, assert failed, ...) are listed first when present.'
      input_schema(
        properties: {
          lines: { type: 'integer', description: 'default 100' },
          since_last: { type: 'boolean', description: 'only what arrived since the previous device_log call' }
        }
      )
      annotations(read_only_hint: false)

      class << self
        def call(lines: 100, since_last: false)
          device_call do
            out, panics = Device.log(lines: lines, since_last: since_last)
            head = panics.empty? ? [] : ["!! crash markers: #{panics.size}", *panics.first(5), '-----']
            text((head + out).join("\n"))
          end
        end
      end
    end
  end
end
