# frozen_string_literal: true

require "io/console"

module EspFlash
  # A serial terminal for the device. Keystrokes reach the device byte for byte, terminal replies included
  # (the answer to a "ESC [5n"/"ESC [6n" query, which the picoruby-shell sends to detect the terminal), and
  # what the device sends is written out as it arrives. Ctrl-C goes to the device too.
  #
  #   Ctrl-]          quit
  #   Ctrl-T Ctrl-R   reset the device (Ctrl-T Ctrl-H lists the menu)
  #
  # When the ELF and the toolchain's addr2line are available, addresses in a panic's backtrace are decoded.
  class Monitor
    EXIT_KEY = 0x1d # Ctrl-]
    MENU_KEY = 0x14 # Ctrl-T
    XTENSA_TARGETS = %w[esp32 esp32s2 esp32s3].freeze

    def initialize(path, baud:, target: nil, elf: nil, reset: true, input: $stdin, output: $stdout)
      @path = path
      @baud = baud
      @reset = reset
      @input = input
      @output = output
      @elf = elf if elf && File.exist?(elf)
      @addr2line = find_addr2line(target) if @elf
      @menu = false
      @line = "".b
      @out_mutex = Mutex.new
    end

    def run
      @port = SerialPort.open(@path, @baud)
      status "--- Monitoring #{@path}#{" at #{@baud} baud" if @port.resettable?}. " \
             "Quit: Ctrl-]  Reset: Ctrl-T Ctrl-R  Help: Ctrl-T Ctrl-H ---"
      reset_device if @reset
      reader = Thread.new { read_loop }
      raw_input { input_loop }
    ensure
      reader&.kill
      @port&.close
    end

    private

    def input_loop
      loop do
        data = begin
          @input.readpartial(1024)
        rescue EOFError
          return
        end
        out = "".b
        data.each_byte do |byte|
          if @menu
            @menu = false
            case byte
            when 0x12, 0x52, 0x72 # Ctrl-R, R, r
              send_to_device(out)
              out = "".b
              reset_device
            when MENU_KEY then out << byte # Ctrl-T Ctrl-T sends Ctrl-T itself
            when 0x18, 0x58, 0x78 # Ctrl-X, X, x
              send_to_device(out)
              return
            else help
            end
          elsif byte == EXIT_KEY
            send_to_device(out)
            return
          elsif byte == MENU_KEY
            @menu = true
          else
            out << byte
          end
        end
        send_to_device(out)
      end
    end

    def read_loop
      loop do
        data = @port.read(4096, 0.2)
        next if data.empty?

        @out_mutex.synchronize do
          @output.write(data)
          @output.flush
        end
        decode_backtrace(data) if @addr2line
      rescue Disconnected
        reconnect
      end
    end

    # A USB serial device can vanish for a moment while the chip resets (e.g. the USB-Serial/JTAG one).
    def reconnect
      status "--- #{@path} disconnected; waiting for it to come back (Ctrl-] to quit) ---"
      @port.close
      loop do
        sleep 0.5
        begin
          @port = SerialPort.open(@path, @baud)
          break
        rescue Error
          next
        end
      end
      status "--- Reconnected to #{@path} ---"
    end

    def send_to_device(bytes)
      @port.write(bytes) unless bytes.empty?
    rescue Disconnected, IOError
      nil # read_loop reconnects
    end

    def reset_device
      return status("--- #{@path} cannot reset the device ---") unless @port.resettable?

      status "--- Resetting the device ---"
      EspFlash.hard_reset(@port)
    end

    def help
      status "--- Ctrl-]: quit  Ctrl-T Ctrl-R: reset  Ctrl-T Ctrl-X: quit  Ctrl-T Ctrl-T: send Ctrl-T ---"
    end

    def status(message)
      @out_mutex.synchronize do
        @output.write("\r\n#{message}\r\n")
        @output.flush
      end
    end

    # Raw mode so that every key (and every terminal reply) is read as it comes, without echo or signals.
    def raw_input(&block)
      return yield unless @input.respond_to?(:tty?) && @input.tty?

      @input.raw(intr: false) do
        windows_vt_mode(&block)
      end
    end

    # The Windows console answers "ESC [6n" and sends keys as escape sequences only in its VT modes.
    def windows_vt_mode
      return yield unless Gem.win_platform?

      require "fiddle/import"
      k32 = Module.new do
        extend Fiddle::Importer
        dlload "kernel32.dll"
        extern "void* GetStdHandle(long)"
        extern "int GetConsoleMode(void*, void*)"
        extern "int SetConsoleMode(void*, unsigned long)"
      end
      saved = [[-10, 0x0200], [-11, 0x0004]].filter_map do |std, flag| # VT input / VT processing
        handle = k32.GetStdHandle(std)
        mode = [0].pack("V")
        next if k32.GetConsoleMode(handle, mode).zero?

        mode = mode.unpack1("V")
        k32.SetConsoleMode(handle, mode | flag)
        [handle, mode]
      end
      begin
        yield
      ensure
        saved.each { |handle, mode| k32.SetConsoleMode(handle, mode) }
      end
    end

    def find_addr2line(target)
      names = if XTENSA_TARGETS.include?(target)
                ["xtensa-esp-elf-addr2line", "xtensa-#{target}-elf-addr2line"]
              else
                ["riscv32-esp-elf-addr2line"]
              end
      exts = Gem.win_platform? ? [".exe", ""] : [""]
      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).product(names, exts).each do |dir, name, ext|
        path = File.join(dir, name + ext)
        return path if File.file?(path) && File.executable?(path)
      end
      nil
    end

    # Decodes the code addresses of a panic's "Backtrace:" line (Xtensa) or "MEPC"/"RA" registers (RISC-V).
    def decode_backtrace(data)
      @line << data
      while (newline = @line.index("\n"))
        line = @line.slice!(0..newline)
        next unless line.match?(/Backtrace:|^\s*(PC|MEPC|RA)\s*:/n)

        addresses = line.scan(/0x4[0-9a-f]{7}/in).uniq
        next if addresses.empty?

        decoded = IO.popen([@addr2line, "-pfiaC", "-e", @elf, *addresses], err: File::NULL, &:read).to_s
        lines = decoded.lines.map(&:chomp).reject { |l| l.include?("?? ??:0") }
        @out_mutex.synchronize do
          lines.each { |l| @output.write("--- #{l}\r\n") }
          @output.flush
        end
      end
      @line = @line.byteslice(-1024..) if @line.bytesize > 4096
    rescue SystemCallError
      @addr2line = nil
    end
  end
end
