# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `device_download`: reads a file from the device over RBTP (rake picomodem:get).
    class DeviceDownload < MCP::Tool
      extend Helpers

      description 'Download a file from the device (RBTP via `rake picomodem:get`, CRC32-checked) and save it ' \
                  'locally. The shell must be at its prompt.'
      input_schema(
        properties: {
          remote_path: { type: 'string' },
          local_path: { type: 'string', description: 'default: basename of remote_path in the current directory' }
        },
        required: ['remote_path']
      )

      class << self
        def call(remote_path:, local_path: nil)
          local_path = File.expand_path(local_path || File.basename(remote_path))
          result = device_call do
            Device.transfer("get #{remote_path}") do |pty|
              CommandRunner.run(RakeTask.command("picomodem:get[#{remote_path},#{local_path}]", native: true),
                                env: { 'PORT' => pty })
            end
          end
          result.is_a?(CommandRunner::Result) ? text(result.output, error: !result.success) : result
        end
      end
    end
  end
end
