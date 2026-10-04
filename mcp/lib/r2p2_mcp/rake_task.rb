# frozen_string_literal: true

module R2p2Mcp
  # Builds the command line / environment for the repository's rake tasks.
  # Docker is the default; `native: true` runs the plain task on the host.
  module RakeTask
    TARGETS = %w[esp32 esp32c3 esp32c6 esp32h2 esp32p4 esp32s3].freeze
    VMS = %w[picoruby femtoruby].freeze

    module_function

    def command(task, native: false)
      ['rake', native ? task : "docker:#{task}"]
    end

    # Environment read by CMake / the rake tasks. `sdkconfigs` are names of
    # fragment files under sdkconfigs/ (e.g. "usb_console").
    def env(sdkconfigs: [], use_wifi: false)
      env = {}
      env['SDKCONFIG_DEFAULTS'] = (['sdkconfig.defaults'] + sdkconfigs.map { |n| "sdkconfigs/#{n}" }).join(';')
      env['USE_WIFI'] = '1' if use_wifi
      env
    end

    def available_sdkconfigs
      Dir[File.join(ROOT, 'sdkconfigs', '*')].map { |f| File.basename(f) }.sort
    end
  end
end
