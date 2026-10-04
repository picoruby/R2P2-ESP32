# frozen_string_literal: true

module R2p2Mcp
  # mrbgems available to the firmware: the ones shipped with picoruby (core) and the project's own
  # (mrbgems/ at the repository root, see Scaffold).
  module Mrbgem
    class Error < StandardError; end

    CORE_DIR = File.join(ROOT, 'components/picoruby-esp32/picoruby/mrbgems')
    CUSTOM_DIR = File.join(ROOT, 'mrbgems')
    PREFIX = 'picoruby-'

    Gem = Struct.new(:name, :kind, :dir, :summary)

    module_function

    def all
      [[:custom, CUSTOM_DIR], [:core, CORE_DIR]].flat_map do |kind, base|
        Dir[File.join(base, "#{PREFIX}*")].select { |dir| File.directory?(dir) }.sort.map do |dir|
          Gem.new(File.basename(dir), kind, dir, summary_of(dir))
        end
      end
    end

    # Finds a gem by its directory name; the `picoruby-` prefix may be left out. Custom gems win.
    def resolve(name)
      all_gems = all
      found = [name, "#{PREFIX}#{name}"].filter_map { |n| all_gems.find { |gem| gem.name == n } }.first
      found or raise Error, "no such mrbgem: #{name} (see mrbgem_list)"
    end

    def summary_of(dir)
      rake = File.join(dir, 'mrbgem.rake')
      File.exist?(rake) ? File.read(rake)[/spec\.summary\s*=\s*['"]([^'"]*)['"]/, 1] : nil
    end
  end
end
