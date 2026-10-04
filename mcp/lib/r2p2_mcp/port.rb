# frozen_string_literal: true

require 'socket'

module R2p2Mcp
  # A duplex byte stream to a picoruby-shell: a serial device, or a TCP socket
  # (QEMU's UART). A reader thread keeps everything received in a bounded
  # buffer addressed by absolute byte positions, so callers can ask for "what
  # arrived since position N" and wait for it.
  class Port
    MAX_BUFFER = 256 * 1024
    DEFAULT_BAUD = 115_200

    attr_reader :target
    attr_writer :tee # called with every chunk received (see PtyBridge)

    def self.open(target, baud: DEFAULT_BAUD)
      io =
        if target.start_with?('tcp://')
          host, port = target.delete_prefix('tcp://').split(':')
          TCPSocket.new(host, Integer(port))
        else
          require 'serialport'
          SerialPort.new(target, baud, 8, 1, SerialPort::NONE)
        end
      new(target, io)
    end

    def self.tcp?(target) = target.start_with?('tcp://')

    def initialize(target, io)
      @target = target
      @io = io
      @buffer = ''.b
      @base = 0 # absolute position of @buffer[0]
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @closed = false
      @eof = false
      @reader = Thread.new { read_loop }
    end

    def write(bytes)
      @io.write(bytes)
      @io.flush
    end

    # Absolute position just past the last received byte.
    def position
      @mutex.synchronize { @base + @buffer.bytesize }
    end

    # Bytes received since +from+ (clamped to what is still buffered).
    def read_since(from)
      @mutex.synchronize { slice_since(from) }
    end

    # Waits until the block returns truthy for the bytes received since +from+,
    # or +timeout+ seconds pass. Returns [bytes, matched].
    def wait_for(from, timeout)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      @mutex.synchronize do
        loop do
          data = slice_since(from)
          return [data, true] if yield(data)

          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return [data, false] if remaining <= 0 || @eof

          @cond.wait(@mutex, remaining)
        end
      end
    end

    # Replaces everything received since +from+ with +text+ (used to keep binary transfers out of the log).
    def replace_since(from, text)
      @mutex.synchronize do
        from = @base if from < @base
        @buffer = @buffer.byteslice(0, from - @base) + text.b
      end
    end

    def eof? = @eof

    def close
      @closed = true
      @reader.join(1)
      @io.close unless @io.closed?
    end

    private

    def slice_since(from)
      from = @base if from < @base
      @buffer.byteslice(from - @base, @buffer.bytesize) || ''.b
    end

    def read_loop
      receive_until_closed
    rescue IOError, SystemCallError
      nil
    ensure
      mark_eof
    end

    def receive_until_closed
      until @closed
        next unless @io.wait_readable(0.2)

        data = @io.read_nonblock(4096, exception: false)
        next if data == :wait_readable
        break if data.nil?

        append(data)
      end
    end

    def mark_eof
      @mutex.synchronize do
        @eof = true
        @cond.broadcast
      end
    end

    def append(data)
      @tee&.call(data)
      @mutex.synchronize do
        @buffer << data.b
        if @buffer.bytesize > MAX_BUFFER
          drop = @buffer.bytesize - MAX_BUFFER
          @buffer = @buffer.byteslice(drop, MAX_BUFFER)
          @base += drop
        end
        @cond.broadcast
      end
    end
  end
end
