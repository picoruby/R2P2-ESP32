# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

module R2p2Mcp
  # The QEMU (ESP32-S3) instance run by `rake qemu_serve`, whose UART is a local TCP port.
  # `rake qemu_serve` builds first, so starting can take minutes the first time.
  module Qemu
    PORT = 5555
    TARGET = "tcp://127.0.0.1:#{PORT}".freeze
    CONTAINER = 'r2p2-esp32-qemu' # keep in sync with DOCKER_QEMU_CONTAINER in rakelib/docker.rake
    READY_MARKER = '[qemu_serve] ready'

    @pid = nil
    @exit_status = nil
    @vm = nil
    @native = false
    @log_dir = Dir.mktmpdir('r2p2-mcp-qemu-')
    @log_path = File.join(@log_dir, 'qemu.log')
    at_exit do
      stop if running?
      FileUtils.rm_rf(@log_dir)
    end

    class << self
      attr_reader :vm, :native, :exit_status

      def running? = !@pid.nil? && @exit_status.nil?

      def ready? = running? && log.include?(READY_MARKER)

      def log = File.exist?(@log_path) ? File.read(@log_path, mode: 'rb').scrub : ''

      def start(vm: nil, native: false)
        raise 'QEMU is already running; qemu_stop it first' if running?

        @vm = vm
        @native = native
        @exit_status = nil
        task = vm ? "#{vm}:qemu_serve" : 'qemu_serve'
        @pid = spawn_serve(RakeTask.command(task, native: native))
        Thread.new { @exit_status = Process.wait2(@pid).last }
      end

      def stop
        return unless running?

        if @native
          Process.kill('TERM', @pid)
        else
          CommandRunner.run(['docker', 'stop', CONTAINER], timeout: 30)
        end
        wait_for_exit(10)
        Process.kill('KILL', @pid) if running?
      rescue Errno::ESRCH
        nil
      end

      private

      def wait_for_exit(seconds)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        sleep 0.2 while running? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      end

      def spawn_serve(command)
        FileUtils.rm_f(@log_path)
        # Don't leak this server's own Bundler environment (mcp/Gemfile) into rake.
        Bundler.with_unbundled_env do
          Process.spawn({ 'QEMU_SERIAL_PORT' => PORT.to_s }, *command, chdir: ROOT, in: File::NULL,
                                                                       out: @log_path, err: %i[child out], pgroup: true)
        end
      end
    end
  end
end
