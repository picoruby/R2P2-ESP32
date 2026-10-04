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
      include Recovery

      attr_reader :port

      def connected? = !@port.nil? && !@port.eof?

      def target = @port&.target

      # Opens the port, nudges the shell with a newline and waits up to +wait+ seconds for its prompt. Nothing
      # else is sent: the device may still be booting, and stray input there can break its start-up.
      def connect(target, baud: Port::DEFAULT_BAUD, wait: 10)
        disconnect
        @port = Port.open(target, baud: baud)
        @log_cursor = @port.position
        start = @port.position
        @port.write("\r")
        _, ok = wait_for_prompt(start, wait)
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

      # Runs a shell command; returns [output_lines, status]. On timeout the command is interrupted with
      # Ctrl-C, then (e.g. irb, which ignores it) Ctrl-D. status is :ok, :timeout (interrupted, back at the
      # prompt), :stuck (could not get back) or :unresponsive (the shell never took the command, see
      # Recovery#interrupt).
      def exec(command, timeout: 10)
        port = port!
        start = port.position
        port.write("#{command}\r")
        _, ok = wait_for_prompt(start, timeout, min_lines: 1)
        status = ok ? :ok : interrupt(port, start, command)
        lines, = Terminal.render(port.read_since(start))
        [lines.drop(1), status] # drop the echoed command line
      end

      # Runs a file transfer through a pty bridged to the connected port: the block gets the pty path and
      # returns a CommandRunner::Result. The binary traffic is replaced in the log by one `[rbtp] label` line.
      def transfer(label)
        port = port!
        start = port.position
        bridge = PtyBridge.new(port)
        result = yield bridge.path
        recover_prompt(port) unless result.success
        result
      ensure
        bridge&.close
        port&.replace_since(start, "[rbtp] #{label}\r\n") if start
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
