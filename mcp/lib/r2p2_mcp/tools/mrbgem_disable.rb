# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `mrbgem_disable`: removes an mrbgem from the build configs.
    class MrbgemDisable < MCP::Tool
      extend Helpers
      extend MrbgemEdit

      description 'Remove an mrbgem from build_config/*.rb (all four by default). Gems provided by a gembox ' \
                  '(see mrbgem_list) cannot be removed this way. Then run build.'
      input_schema(
        properties: {
          name: { type: 'string' },
          vm: { type: 'string', enum: BuildConfig::VMS, description: 'default: both' },
          arch: { type: 'string', enum: BuildConfig::ARCHS, description: 'default: both' }
        },
        required: ['name']
      )

      class << self
        def call(name:, vm: nil, arch: nil)
          edit(name, vm, arch) { |path, gem| BuildConfig.disable(path, gem) }
        end
      end
    end
  end
end
