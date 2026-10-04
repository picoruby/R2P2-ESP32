# frozen_string_literal: true

module R2p2Mcp
  module Device
    # Getting the device and its shell back: reset, interrupting a hung command, waking a shell that did not
    # start. Mixed into Device's singleton class, so it uses Device.port! and Device.wait_for_prompt.
    module Recovery
      # `reboot` the device and return [boot log up to the next prompt, whether it came back, how it was reset].
      # Boot can take up to a minute on some builds, so it is waited for passively. Only if the prompt does not
      # come, a serial device is reset through DTR/RTS (what esptool does) and waited for once more.
      def reset(timeout: 60)
        port = port!
        start = port.position
        port.write("reboot\r")
        _, ok = wait_for_prompt(start, timeout, min_lines: 2)
        method = 'reboot'
        method, ok = hard_reset(port, start, timeout) if !ok && port.serial?
        lines, partial = Terminal.render(port.read_since(start))
        [lines.drop(1) + [partial], ok, method]
      end

      private

      # A transfer that failed midway can leave the shell inside a half-started session (it times out
      # after a few seconds) or with stray input; wait until the prompt is back.
      def recover_prompt(port)
        start = port.position
        port.write("\r")
        wait_for_prompt(start, 8)
      end

      def hard_reset(port, start, timeout)
        port.hard_reset
        _, ok = wait_for_prompt(start, timeout, min_lines: 2)
        ['DTR/RTS hard reset', ok]
      end

      # Gets a hung command back to the prompt: :timeout when that worked, :stuck when not. When the shell never
      # echoed the command, nothing is sent (the device may be booting, where a Ctrl-C breaks the shell's
      # start-up, or hung): :unresponsive.
      def interrupt(port, start, command)
        lines, = Terminal.render(port.read_since(start))
        return :unresponsive unless lines.any? { |line| line.end_with?(command) }

        port.write("\x03")
        return :timeout if wait_for_prompt(start, 2, min_lines: 1).last

        port.write("\x04") # only sent while no prompt is showing, so it never logs out the shell
        wait_for_prompt(start, 2, min_lines: 1).last ? :timeout : :stuck
      end
    end
  end
end
