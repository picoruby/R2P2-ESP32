# frozen_string_literal: true

module R2p2Mcp
  module Tools
    # MCP tool `qemu_start`: runs the firmware on QEMU and connects to its UART.
    class QemuStart < MCP::Tool
      extend Helpers

      description 'Run the firmware on QEMU (ESP32-S3; no hardware or peripherals) and connect to its shell, so ' \
                  'device_exec / device_upload / ... work as on a real board. Builds build-qemu first (set up ' \
                  'automatically; the first time takes minutes) and starts from a fresh /home every time. ' \
                  'Docker by default. Replaces any current connection.'
      input_schema(
        properties: {
          vm: { type: 'string', enum: RakeTask::VMS, description: 'omit to keep the configured VM' },
          native: { type: 'boolean', description: 'run on the host (needs ESP-IDF) instead of Docker' },
          timeout: { type: 'number', description: 'seconds to wait for the shell, default 120' }
        }
      )

      class << self
        def call(vm: nil, native: false, timeout: 120)
          return text('QEMU is already running; qemu_stop it first', error: true) if Qemu.running?

          Device.disconnect
          Qemu.start(vm: vm, native: native)
          deadline = monotonic + timeout
          return waiting_message(timeout) unless wait_until(deadline) { Qemu.ready? || !Qemu.running? }
          return failed_message unless Qemu.running?

          connected = connected_before?(deadline)
          connected ? text("QEMU is running; connected to #{Qemu::TARGET}, shell prompt seen") : not_yet(timeout)
        end

        private

        def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        def wait_until(deadline)
          sleep 0.5 until yield || monotonic > deadline
          yield
        end

        # Docker publishes the port before QEMU listens, so early connections are accepted and then dropped.
        def connected_before?(deadline)
          while monotonic < deadline && Qemu.running?
            begin
              return true if Device.connect(Qemu::TARGET) && Device.connected?
            rescue IOError, SystemCallError
              nil
            end
            sleep 1
          end
          false
        end

        def waiting_message(timeout)
          text("QEMU is still building / starting after #{timeout}s and keeps going in the background. " \
               'Check qemu_status, then serial_connect tcp://127.0.0.1:5555 once it is up.')
        end

        def not_yet(timeout)
          text("QEMU is running, but no shell prompt within #{timeout}s. Check qemu_status.", error: true)
        end

        def failed_message
          text("QEMU exited (status #{Qemu.exit_status&.exitstatus.inspect}).\n#{Qemu.log.lines.last(30).join}",
               error: true)
        end
      end
    end
  end
end
