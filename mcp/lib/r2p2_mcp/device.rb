# frozen_string_literal: true

module R2p2Mcp
  # The one connected Port plus the shell-level operations built on it.
  module Device
    PROMPT = '$> '
    PANIC_PATTERN = /Guru Meditation|abort\(\) was called|assert failed|Backtrace:|Rebooting\.\.\./

    class NotConnected < StandardError; end

    @port = nil
    @log_cursor = 0

    class << self
      attr_reader :port

      def connected? = !@port.nil? && !@port.eof?

      def target = @port&.target

      def connect(target, baud: Port::DEFAULT_BAUD)
        disconnect
        @port = Port.open(target, baud: baud)
        @log_cursor = @port.position
        # Wake the shell and see whether it answers with a prompt.
        start = @port.position
        @port.write("\r")
        _, ok = wait_for_prompt(start, 3)
        ok
      end

      def disconnect
        @port&.close
        @port = nil
      end

      def port!
        raise NotConnected, 'not connected; call serial_connect first' unless @port
        raise NotConnected, "the connection to #{@port.target} was closed by the device" if @port.eof?

        @port
      end

      # Runs a shell command; returns [output_lines, status]. On timeout the
      # command is interrupted with Ctrl-C, then (e.g. irb, which ignores it)
      # Ctrl-D. status is :ok, :timeout (back at the prompt) or :stuck.
      def exec(command, timeout: 10)
        port = port!
        start = port.position
        port.write("#{command}\r")
        _, ok = wait_for_prompt(start, timeout, min_lines: 1)
        status = ok ? :ok : interrupt(port, start)
        lines, = Terminal.render(port.read_since(start))
        [lines.drop(1), status] # drop the echoed command line
      end

      # `reboot` the device and return the boot log up to the next prompt.
      def reset(timeout: 30)
        port = port!
        start = port.position
        port.write("reboot\r")
        _, ok = wait_for_prompt(start, timeout, min_lines: 2)
        lines, partial = Terminal.render(port.read_since(start))
        [lines.drop(1) + [partial], ok]
      end

      # Last +lines+ lines of the buffer, or everything since the last call.
      def log(lines: 100, since_last: false)
        port = port!
        from = since_last ? @log_cursor : 0
        @log_cursor = port.position
        out, partial = Terminal.render(port.read_since(from))
        out << partial unless partial.empty?
        out = out.last(lines)
        [out, out.grep(PANIC_PATTERN)]
      end

      private

      # Gets a hung command back to the prompt: :timeout when that worked, else :stuck.
      def interrupt(port, start)
        port.write("\x03")
        return :timeout if wait_for_prompt(start, 2, min_lines: 1).last

        port.write("\x04") # only sent while no prompt is showing, so it never logs out the shell
        wait_for_prompt(start, 2, min_lines: 1).last ? :timeout : :stuck
      end

      # Waits until the rendered stream ends with the prompt on an otherwise
      # empty line, after at least +min_lines+ completed lines.
      def wait_for_prompt(start, timeout, min_lines: 0)
        port!.wait_for(start, timeout) do |bytes|
          lines, partial = Terminal.render(bytes)
          partial == PROMPT && lines.size >= min_lines
        end
      end
    end
  end
end
