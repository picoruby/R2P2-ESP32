# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `setup`: sets up the build for a target as a background job.
    class Setup < MCP::Tool
      extend Helpers

      description 'Set up the build for a target (rake setup_<target>; first time, or when the target / sdkconfigs / ' \
                  'use_wifi change). ' \
                  'Runs as a background job in Docker by default. Deletes the old sdkconfig first.'
      input_schema(
        properties: {
          target: { type: 'string', enum: RakeTask::TARGETS, description: 'ESP32 chip' },
          sdkconfigs: { type: 'array', items: { type: 'string' },
                        description: "Fragment names under sdkconfigs/ (#{RakeTask.available_sdkconfigs.join(', ')})" },
          use_wifi: { type: 'boolean', description: 'Compile WiFi support (USE_WIFI=1)' },
          native: { type: 'boolean', description: 'Run on the host instead of Docker' }
        },
        required: ['target']
      )

      class << self
        def call(target:, sdkconfigs: [], use_wifi: false, native: false)
          unknown = sdkconfigs - RakeTask.available_sdkconfigs
          return text("unknown sdkconfigs: #{unknown.join(', ')}", error: true) unless unknown.empty?

          # sdkconfig caches SDKCONFIG_DEFAULTS; README: delete it when they change.
          FileUtils.rm_f(File.join(ROOT, 'sdkconfig'))
          start_job(
            label: "setup #{target}",
            command: RakeTask.command("setup_#{target}", native: native),
            env: RakeTask.env(sdkconfigs: sdkconfigs, use_wifi: use_wifi)
          )
        end
      end
    end
  end
end
