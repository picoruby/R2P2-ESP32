# frozen_string_literal: true

require 'fileutils'

module R2p2Mcp
  # Creates the skeleton of a pure-Ruby mrbgem (works on both VMs) under mrbgems/ at the repository root.
  module Scaffold
    NAME_PATTERN = /\A[a-z][a-z0-9_]*\z/

    module_function

    # Returns the created directory. +name+ is without the `picoruby-` prefix, e.g. "my_sensor".
    def create(name, summary: nil, author: nil)
      raise Mrbgem::Error, "invalid name #{name.inspect}: use lower_snake_case" unless name.match?(NAME_PATTERN)

      dir = File.join(Mrbgem::CUSTOM_DIR, "#{Mrbgem::PREFIX}#{name}")
      raise Mrbgem::Error, "already exists: #{dir}" if File.exist?(dir)

      files(name, summary || "#{name} for PicoRuby", author || git_user).each do |path, body|
        FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
        File.write(File.join(dir, path), body)
      end
      dir
    end

    def git_user
      name = IO.popen(%w[git config user.name], err: File::NULL, &:read).to_s.strip
      name.empty? ? 'Your Name' : name
    end

    def class_name(name)
      name.split('_').map(&:capitalize).join
    end

    def files(name, summary, author)
      klass = class_name(name)
      {
        'mrbgem.rake' => rake(name, summary, author),
        "mrblib/#{name}.rb" => "class #{klass}\n  def self.hello\n    \"Hello from #{name}\"\n  end\nend\n",
        "sig/#{name}.rbs" => "class #{klass}\n  def self.hello: () -> String\nend\n",
        "test/#{name}_test.rb" => test(name, klass),
        'README.md' => readme(name, klass, summary)
      }
    end

    def rake(name, summary, author)
      <<~RUBY
        MRuby::Gem::Specification.new('#{Mrbgem::PREFIX}#{name}') do |spec|
          spec.license = 'MIT'
          spec.author  = '#{author}'
          spec.summary = '#{summary}'
        end
      RUBY
    end

    def test(name, klass)
      <<~RUBY
        class #{klass}Test < Picotest::Test
          def setup
            require "#{name}"
          end

          def test_hello
            assert_equal "Hello from #{name}", #{klass}.hello
          end
        end
      RUBY
    end

    def readme(name, klass, summary)
      <<~MARKDOWN
        # #{Mrbgem::PREFIX}#{name}

        #{summary}

        ## Usage

        ```ruby
        require '#{name}'

        puts #{klass}.hello
        ```
      MARKDOWN
    end
  end
end
