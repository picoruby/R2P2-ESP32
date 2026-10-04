# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `build`: builds the firmware.
    class Build < MCP::Tool
      extend Helpers

      description 'Build the firmware (rake picoruby:build / femtoruby:build). Docker by default. Run setup first; ' \
                  'pass the same sdkconfigs / use_wifi as setup. Waits for it to finish (see timeout).'
      input_schema(
        properties: {
          vm: { type: 'string', enum: RakeTask::VMS,
                description: 'picoruby (mruby, default) or femtoruby (mruby/c)' },
          sdkconfigs: { type: 'array', items: { type: 'string' } },
          use_wifi: { type: 'boolean' },
          native: { type: 'boolean', description: 'Run on the host instead of Docker' },
          timeout: WAIT_PROPERTY
        }
      )

      class << self
        def call(vm: 'picoruby', sdkconfigs: [], use_wifi: false, native: false, timeout: DEFAULT_WAIT)
          run_job(
            label: "build #{vm}",
            command: RakeTask.command("#{vm}:build", native: native),
            env: RakeTask.env(sdkconfigs: sdkconfigs, use_wifi: use_wifi),
            timeout: timeout
          )
        end
      end
    end
  end
end
