# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `mrbgem_list`: which mrbgems exist and which of them the firmware builds.
    class MrbgemList < MCP::Tool
      extend Helpers

      description 'List mrbgems (custom ones from mrbgems/ first, then picoruby\'s) and in which build configs ' \
                  'each is enabled (build_config/<arch>-esp-<vm>.rb). "via X" means a gembox provides it.'
      input_schema(
        properties: {
          query: { type: 'string', description: 'only gems whose name or summary contains this' },
          enabled_only: { type: 'boolean' }
        }
      )
      annotations(read_only_hint: true)

      class << self
        def call(query: nil, enabled_only: false)
          states = BuildConfig.paths.to_h { |path| [BuildConfig.label(path), BuildConfig.enabled(path)] }
          rows = Mrbgem.all.select { |gem| matches?(gem, query) }.filter_map { |gem| row(gem, states, enabled_only) }
          text(rows.empty? ? 'no matching mrbgems' : rows.join("\n"))
        end

        private

        def matches?(gem, query)
          query.nil? || "#{gem.name} #{gem.summary}".downcase.include?(query.downcase)
        end

        def row(gem, states, enabled_only)
          where = states.select { |_label, gems| gems.key?(gem.name) }
          return if enabled_only && where.empty?

          status = where.empty? ? 'not enabled' : describe(where, gem.name)
          "#{gem.name}#{' [custom]' if gem.kind == :custom}: #{status}#{" - #{gem.summary}" if gem.summary}"
        end

        def describe(where, name)
          via = where.values.filter_map { |gems| gems[name] }.uniq
          configs = where.size == BuildConfig.paths.size ? 'all configs' : where.keys.join(', ')
          "#{configs}#{" (via #{via.join(', ')})" unless via.empty?}"
        end
      end
    end
  end
end
