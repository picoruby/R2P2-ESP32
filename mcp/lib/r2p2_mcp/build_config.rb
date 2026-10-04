# frozen_string_literal: true

module R2p2Mcp
  # Reads and edits which mrbgems the firmware builds, in components/picoruby-esp32/build_config/*.rb
  # (one file per architecture x VM).
  module BuildConfig
    DIR = File.join(ROOT, 'components/picoruby-esp32/build_config')
    VMS = %w[picoruby femtoruby].freeze
    ARCHS = %w[xtensa riscv].freeze
    GEM_LINE = /^\s*conf\.gem\s/

    module_function

    # Config files for the given VM / architecture (nil = all of them).
    def paths(vm: nil, arch: nil)
      (vm ? [vm] : VMS).product(arch ? [arch] : ARCHS).map { |v, a| File.join(DIR, "#{a}-esp-#{v}.rb") }
    end

    def label(path)
      arch, _, vm = File.basename(path, '.rb').partition('-esp-')
      "#{arch}/#{vm}"
    end

    # Gem directory name of a `conf.gem` line (`core: 'x'` or `gemdir: '.../x'`), or nil.
    def gem_name(line)
      line[/conf\.gem\s+core:\s*['"]([^'"]+)['"]/, 1] || line[/conf\.gem\s+gemdir:.*?([\w.-]+)['"]/, 1]
    end

    # { gem name => nil (listed in the file) or the gembox that provides it }
    def enabled(path)
      lines = File.readlines(path)
      gems = lines.filter_map { |line| gem_name(line) }.to_h { |name| [name, nil] }
      lines.filter_map { |line| line[/conf\.gembox\s+['"]([^'"]+)['"]/, 1] }.each do |box|
        gembox_gems(box).each { |name| gems[name] ||= box }
      end
      gems
    end

    # Gems named in a gembox (conditions such as `if posix?` are ignored).
    def gembox_gems(box)
      file = File.join(Mrbgem::CORE_DIR, "#{box}.gembox")
      File.exist?(file) ? File.readlines(file).filter_map { |line| gem_name(line) } : []
    end

    def line_for(gem)
      if gem.kind == :custom
        "  conf.gem gemdir: File.expand_path('../../../mrbgems/#{gem.name}', __dir__)\n"
      else
        "  conf.gem core: '#{gem.name}'\n"
      end
    end

    # Adds the gem after the last `conf.gem` line. Returns :added, :already or :gembox.
    def enable(path, gem)
      state = enabled(path)
      return state[gem.name].nil? ? :already : :gembox if state.key?(gem.name)

      lines = File.readlines(path)
      lines.insert(insertion_index(lines), line_for(gem))
      File.write(path, lines.join)
      :added
    end

    # Index to insert a new `conf.gem` line at: after the last one, else before the closing `end`.
    def insertion_index(lines)
      last_gem = lines.rindex { |line| line.match?(GEM_LINE) }
      last_gem ? last_gem + 1 : lines.rindex { |line| line.match?(/^end\b/) }
    end

    # Removes the gem's line. Returns :removed, :absent or :gembox (cannot be removed by editing the file).
    def disable(path, gem)
      state = enabled(path)
      return :absent unless state.key?(gem.name)
      return :gembox unless state[gem.name].nil?

      lines = File.readlines(path).reject { |line| line.match?(GEM_LINE) && gem_name(line) == gem.name }
      File.write(path, lines.join)
      :removed
    end
  end
end
