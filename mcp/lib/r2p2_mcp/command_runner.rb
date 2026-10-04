# frozen_string_literal: true

require 'open3'

module R2p2Mcp
  # Runs a command to completion and captures its output (for short, synchronous steps).
  module CommandRunner
    Result = Struct.new(:output, :success)

    # Runs from the repository root without this server's own Bundler environment (see JobManager).
    def self.run(command, env: {}, timeout: 120)
      Bundler.with_unbundled_env do
        Open3.popen2e(env, *command, chdir: ROOT) do |stdin, out, waiter|
          stdin.close
          reader = Thread.new { out.read.to_s.scrub }
          next Result.new("#{reader.value}\n[timeout after #{timeout}s]", false) unless finished?(waiter, timeout)

          Result.new(reader.value, waiter.value.success?)
        end
      end
    end

    def self.finished?(waiter, timeout)
      return true if waiter.join(timeout)

      Process.kill('TERM', waiter.pid)
      waiter.join(2)
      false
    end
  end
end
