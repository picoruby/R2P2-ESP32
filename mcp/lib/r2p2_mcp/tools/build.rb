# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `build`: builds the firmware as a background job.
    class Build < MCP::Tool
      extend Helpers

      description 'Build the firmware (rake build / picoruby:build / femtoruby:build). Runs as a background job in ' \
                  'Docker by default. ' \
                  'Run setup first. Pass the same sdkconfigs / use_wifi as setup.'
      input_schema(
        properties: {
          vm: { type: 'string', enum: RakeTask::VMS,
                description: 'picoruby (mruby) or femtoruby (mruby/c); omit to keep the configured VM' },
          sdkconfigs: { type: 'array', items: { type: 'string' } },
          use_wifi: { type: 'boolean' },
          native: { type: 'boolean', description: 'Run on the host instead of Docker' }
        }
      )

      class << self
        def call(vm: nil, sdkconfigs: [], use_wifi: false, native: false)
          start_job(
            label: "build#{" #{vm}" if vm}",
            command: RakeTask.command(vm ? "#{vm}:build" : 'build', native: native),
            env: RakeTask.env(sdkconfigs: sdkconfigs, use_wifi: use_wifi)
          )
        end
      end
    end
  end
end
