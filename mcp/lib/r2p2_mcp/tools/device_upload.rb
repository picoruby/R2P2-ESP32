# frozen_string_literal: true

require 'tempfile'

module R2p2Mcp
  module Tools
    # MCP tool `device_upload`: writes a file to the device over RBTP (rake picomodem:put).
    class DeviceUpload < MCP::Tool
      extend Helpers

      description 'Upload a file to the device (RBTP via `rake picomodem:put`, CRC32-checked). Give either ' \
                  'local_path (a file on this machine) or content (the file body as text). The shell must be ' \
                  'at its prompt. Relative remote paths are resolved by the device (its working directory is /home).'
      input_schema(
        properties: {
          remote_path: { type: 'string', description: 'e.g. /home/app.rb; default: basename of local_path' },
          local_path: { type: 'string' },
          content: { type: 'string', description: 'file body, instead of local_path' }
        }
      )

      class << self
        def call(remote_path: nil, local_path: nil, content: nil)
          return text('give exactly one of local_path or content', error: true) if local_path.nil? == content.nil?

          remote_path ||= local_path && File.basename(local_path)
          return text('remote_path is required with content', error: true) unless remote_path

          content ? upload_content(content, remote_path) : upload(File.expand_path(local_path), remote_path)
        end

        private

        def upload_content(content, remote_path)
          Tempfile.create('r2p2-mcp-upload') do |file|
            file.binmode
            file.write(content)
            file.flush
            upload(file.path, remote_path)
          end
        end

        def upload(local_path, remote_path)
          return text("no such file: #{local_path}", error: true) unless File.file?(local_path)

          result = device_call do
            Device.transfer("put #{remote_path}") do |pty|
              CommandRunner.run(RakeTask.command("picomodem:put[#{local_path},#{remote_path}]", native: true),
                                env: { 'PORT' => pty })
            end
          end
          result.is_a?(CommandRunner::Result) ? text(result.output, error: !result.success) : result
        end
      end
    end
  end
end
