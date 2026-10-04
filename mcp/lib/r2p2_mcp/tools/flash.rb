# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `flash`: flashes the built firmware from the host.
    class Flash < MCP::Tool
      extend Helpers

      description 'Flash the built firmware from the host (rake flash; the container cannot see the serial port). ' \
                  'A connected serial port is released first and reconnected afterwards. Background job.'
      input_schema(
        properties: {
          port: { type: 'string',
                  description: 'serial device; default: the connected one, else auto-detected by the flasher' },
          reconnect: { type: 'boolean',
                       description: 'reconnect to the same port after a successful flash (default true)' }
        }
      )

      class << self
        def call(port: nil, reconnect: true)
          current = Device.target
          if current && Port.tcp?(current)
            return text("the connected port #{current} is not a serial device; disconnect it first",
                        error: true)
          end

          port ||= current
          Device.disconnect
          start_job(label: 'flash', command: RakeTask.command('flash', native: true),
                    env: port ? { 'PORT' => port } : {},
                    on_finish: (reconnector(port) if reconnect && port))
        end

        private

        # Reconnects after a successful flash; failures are appended to the job log.
        def reconnector(port)
          lambda do |job|
            next unless job.exit_code.zero?

            sleep 2 # the device resets after flashing
            Device.connect(port)
          rescue StandardError => e
            File.write(job.log_path, "reconnect to #{port} failed: #{e.message}\n", mode: 'a')
          end
        end
      end
    end
  end
end
