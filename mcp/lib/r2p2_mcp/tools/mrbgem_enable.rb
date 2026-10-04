# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # Shared by mrbgem_enable and mrbgem_disable: resolve the gem, edit each selected build config.
    module MrbgemEdit
      RESULTS = {
        added: 'added', removed: 'removed', already: 'already enabled', absent: 'not enabled',
        gembox: 'provided by a gembox; not changed'
      }.freeze

      def edit(name, vm, arch)
        gem = Mrbgem.resolve(name)
        results = BuildConfig.paths(vm: vm, arch: arch).to_h { |path| [BuildConfig.label(path), yield(path, gem)] }
        text("#{gem.name}\n#{report(results)}")
      rescue Mrbgem::Error => e
        text(e.message, error: true)
      end

      def report(results)
        lines = results.map { |label, result| "#{label}: #{RESULTS.fetch(result)}" }
        lines << 'Run build to apply.' if results.values.intersect?(%i[added removed])
        lines.join("\n")
      end
    end

    # MCP tool `mrbgem_enable`: adds an mrbgem to the build configs.
    class MrbgemEnable < MCP::Tool
      extend Helpers
      extend MrbgemEdit

      description 'Build an mrbgem into the firmware: adds it to build_config/*.rb (all four by default). ' \
                  'name is the directory name, with or without the `picoruby-` prefix. Then run build.'
      input_schema(
        properties: {
          name: { type: 'string' },
          vm: { type: 'string', enum: BuildConfig::VMS, description: 'default: both' },
          arch: { type: 'string', enum: BuildConfig::ARCHS, description: 'xtensa (esp32, s2, s3) or riscv; default: both' }
        },
        required: ['name']
      )

      class << self
        def call(name:, vm: nil, arch: nil)
          edit(name, vm, arch) { |path, gem| BuildConfig.enable(path, gem) }
        end
      end
    end
  end
end
