# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `mrbgem_scaffold`: creates the skeleton of a custom mrbgem.
    class MrbgemScaffold < MCP::Tool
      extend Helpers

      description 'Create a custom pure-Ruby mrbgem skeleton in mrbgems/picoruby-<name>/ (mrbgem.rake, mrblib, ' \
                  'sig, test, README), usable on both VMs as `require "<name>"`. Enable it with mrbgem_enable, ' \
                  'or pass enable: true.'
      input_schema(
        properties: {
          name: { type: 'string', description: 'lower_snake_case, without the picoruby- prefix, e.g. my_sensor' },
          summary: { type: 'string' },
          author: { type: 'string', description: 'default: git user.name' },
          enable: { type: 'boolean', description: 'also add it to all build configs' }
        },
        required: ['name']
      )

      class << self
        def call(name:, summary: nil, author: nil, enable: false)
          dir = Scaffold.create(name, summary: summary, author: author)
          files = Dir[File.join(dir, '**', '*')].select { |f| File.file?(f) }.map { |f| f.delete_prefix("#{ROOT}/") }
          text("created #{dir.delete_prefix("#{ROOT}/")}\n#{files.join("\n")}\n#{next_step(name, enable)}")
        rescue Mrbgem::Error => e
          text(e.message, error: true)
        end

        private

        def next_step(name, enable)
          return "Next: mrbgem_enable #{name}, then build." unless enable

          gem = Mrbgem.resolve(name)
          BuildConfig.paths.each { |path| BuildConfig.enable(path, gem) }
          'Enabled in all build configs. Next: build.'
        end
      end
    end
  end
end
