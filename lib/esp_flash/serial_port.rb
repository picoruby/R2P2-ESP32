# frozen_string_literal: true

require "io/wait"
require "socket"

module EspFlash
  # A serial port without any gem or C extension. Every backend has the same interface:
  #   read(max, timeout)   up to +max+ bytes, waiting up to +timeout+ seconds for the first one ("" if none)
  #   write(bytes)
  #   baud = rate
  #   set_lines(dtr:, rts:) asserts (true) / deasserts (false) DTR and RTS; nil leaves a line as it is
  #   discard_input        drops whatever has been received so far
  #   resettable?          false when DTR/RTS do not reach a chip (a TCP socket)
  #   close
  #
  # "socket://HOST:PORT" opens a TCP connection instead (e.g. QEMU's UART).
  module SerialPort
    def self.open(path, baud)
      if path.start_with?("socket://")
        TcpPort.new(path, baud)
      elsif Gem.win_platform?
        WindowsPort.new(path, baud)
      else
        PosixPort.new(path, baud)
      end
    end

    # Serial ports that are likely to be a USB-connected board.
    def self.candidates
      if Gem.win_platform?
        WindowsPort.list
      elsif RUBY_PLATFORM.include?("darwin")
        Dir["/dev/cu.{usbserial,usbmodem,SLAB_USBtoUART,wchusbserial}*"].sort
      else
        Dir["/dev/tty{USB,ACM}*"].sort
      end
    end

    # The port to use: +given+ (e.g. ENV['PORT']) if set, the only candidate, or one the user picks when
    # there are several and stdin is a terminal.
    def self.resolve(given)
      return given if given && !given.empty?

      ports = candidates
      case ports.size
      when 0
        raise Error, "No serial port found. Connect the board, or set PORT (e.g. PORT=/dev/ttyUSB0)."
      when 1
        ports.first
      else
        raise Error, "Several serial ports found (#{ports.join(", ")}); set PORT to pick one." unless $stdin.tty?

        $stderr.puts "Several serial ports found:"
        ports.each_with_index { |port, i| $stderr.puts "  #{i + 1}) #{port}" }
        $stderr.print "Select one [1-#{ports.size}]: "
        index = Integer($stdin.gets.to_s.strip, exception: false)
        raise Error, "No port selected." unless index && (1..ports.size).cover?(index)

        ports[index - 1]
      end
    end

    # A USB serial device on Linux/macOS, set up with stty(1) and its modem lines driven with ioctl(2).
    class PosixPort
      LINUX = RUBY_PLATFORM.include?("linux")
      TIOCMGET = LINUX ? 0x5415 : 0x4004746a
      TIOCMSET = LINUX ? 0x5418 : 0x8004746d
      TIOCM_DTR = 0x002
      TIOCM_RTS = 0x004

      # struct termios2 (asm-generic/termbits.h): 4 x u32 flags, c_line, c_cc[19], u32 c_ispeed/c_ospeed.
      # BOTHER takes any rate from c_ispeed/c_ospeed.
      TCGETS2 = 0x802c542a
      TCSETS2 = 0x402c542b
      TERMIOS2 = "V4Ca19VV"
      CBAUD = 0o010017
      BOTHER = 0o010000
      CSIZE = 0o000060
      CS8 = 0o000060
      CSTOPB = 0o000100
      CREAD = 0o000200
      PARENB = 0o000400
      CLOCAL = 0o004000
      CRTSCTS = 0o20000000000
      VTIME = 5
      VMIN = 6

      attr_reader :path

      def initialize(path, baud)
        @path = path
        @io = File.open(path, File::RDWR | File::NOCTTY | File::NONBLOCK)
        @io.binmode
        @io.sync = true
        self.baud = baud
      rescue SystemCallError => e
        @io&.close
        raise Error, "Cannot open #{path}: #{e.message}"
      end

      def resettable? = true

      # ESP-IDF's USB-Serial/JTAG controller (VID:PID 303a:1001), known on Linux only (nil elsewhere).
      def usb_jtag_serial?
        return nil unless LINUX

        dir = File.realpath("/sys/class/tty/#{File.basename(File.realpath(@path))}/device")
        dir = File.dirname(dir) until dir == "/" || File.exist?(File.join(dir, "idVendor"))
        return false if dir == "/"

        File.read(File.join(dir, "idVendor")).strip == "303a" && File.read(File.join(dir, "idProduct")).strip == "1001"
      rescue SystemCallError
        nil
      end

      # Raw 8N1 without flow control at +baud+.
      def baud=(baud)
        LINUX ? linux_termios2(baud) : stty(baud)
      rescue SystemCallError => e
        raise Error, "Cannot set #{@path} to #{baud} baud: #{e.message}"
      end

      def read(max, timeout)
        return "".b unless @io.wait_readable(timeout)

        data = @io.read_nonblock(max, exception: false)
        data.is_a?(String) ? data : "".b
      rescue EOFError, Errno::EIO, Errno::ENXIO => e
        raise Disconnected, "#{@path}: #{e.message}"
      end

      def write(bytes)
        @io.write(bytes)
      rescue Errno::EIO, Errno::ENXIO => e
        raise Disconnected, "#{@path}: #{e.message}"
      end

      # Both lines change in one ioctl when both are given (what esptool's "tight" reset relies on).
      def set_lines(dtr: nil, rts: nil)
        buf = [0].pack("i")
        @io.ioctl(TIOCMGET, buf)
        bits = buf.unpack1("i")
        bits = dtr ? bits | TIOCM_DTR : bits & ~TIOCM_DTR unless dtr.nil?
        bits = rts ? bits | TIOCM_RTS : bits & ~TIOCM_RTS unless rts.nil?
        @io.ioctl(TIOCMSET, [bits].pack("i"))
      end

      def discard_input
        loop { break if read(4096, 0).empty? }
      end

      def close
        @io.close unless @io.closed?
      end

      private

      def linux_termios2(baud)
        buf = "\0".b * 44
        @io.ioctl(TCGETS2, buf)
        _iflag, _oflag, cflag, _lflag, line, cc, = buf.unpack(TERMIOS2)
        cflag &= ~(CBAUD | CSIZE | CSTOPB | PARENB | CRTSCTS)
        cflag |= BOTHER | CS8 | CREAD | CLOCAL
        cc = cc.b
        cc.setbyte(VTIME, 0)
        cc.setbyte(VMIN, 1)
        @io.ioctl(TCSETS2, [0, 0, cflag, 0, line, cc, baud, baud].pack(TERMIOS2))
      end

      # stty(1) sets up its stdin, which is this port (kept open, so the settings stay).
      def stty(baud)
        ok = system("stty", baud.to_s, "raw", "-echo", "cs8", "-cstopb", "-parenb", "-crtscts", "clocal", "cread",
                    in: @io, err: File::NULL)
        raise Error, "Cannot set #{@path} to #{baud} baud (stty failed)" unless ok
      end
    end

    # A TCP connection, e.g. to QEMU's UART. There are no modem lines, so the chip cannot be reset.
    class TcpPort
      attr_reader :path

      def initialize(path, _baud)
        @path = path
        host, port = path.delete_prefix("socket://").split(":", 2)
        @io = Socket.tcp(host, Integer(port), connect_timeout: 5)
        @io.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      rescue SystemCallError, SocketError, ArgumentError, TypeError => e
        raise Error, "Cannot connect to #{path}: #{e.message}"
      end

      def resettable? = false
      def usb_jtag_serial? = false
      def baud=(_baud); end
      def set_lines(dtr: nil, rts: nil); end

      def read(max, timeout)
        return "".b unless @io.wait_readable(timeout)

        @io.read_nonblock(max)
      rescue IO::WaitReadable
        "".b
      rescue EOFError, SystemCallError => e
        raise Disconnected, "#{@path}: #{e.message}"
      end

      def write(bytes)
        @io.write(bytes)
      rescue SystemCallError => e
        raise Disconnected, "#{@path}: #{e.message}"
      end

      def discard_input
        loop { break if read(4096, 0).empty? }
      end

      def close
        @io.close unless @io.closed?
      end
    end

    # A COM port on Windows, through kernel32 with Fiddle.
    class WindowsPort
      GENERIC_READ_WRITE = 0xC0000000
      OPEN_EXISTING = 3
      MAXDWORD = 0xFFFFFFFF
      SETRTS = 3
      CLRRTS = 4
      SETDTR = 5
      CLRDTR = 6
      PURGE_RXCLEAR = 0x0008

      def self.kernel32
        @kernel32 ||= begin
          require "fiddle/import"
          Module.new do
            extend Fiddle::Importer
            dlload "kernel32.dll"
            extern "void* CreateFileW(void*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*)"
            extern "int GetCommState(void*, void*)"
            extern "int SetCommState(void*, void*)"
            extern "int SetCommTimeouts(void*, void*)"
            extern "int ReadFile(void*, void*, unsigned long, void*, void*)"
            extern "int WriteFile(void*, void*, unsigned long, void*, void*)"
            extern "int EscapeCommFunction(void*, unsigned long)"
            extern "int PurgeComm(void*, unsigned long)"
            extern "int CloseHandle(void*)"
            extern "unsigned long GetLastError()"
          end
        end
      end

      def self.list
        require "win32/registry"
        Win32::Registry::HKEY_LOCAL_MACHINE.open('HARDWARE\DEVICEMAP\SERIALCOMM') do |key|
          key.map { |_name, _type, value| value }.sort_by { |name| name[/\d+/].to_i }
        end
      rescue LoadError, StandardError
        []
      end

      attr_reader :path

      def initialize(path, baud)
        @path = path
        @k = self.class.kernel32
        name = path.start_with?("\\\\.\\") ? path : "\\\\.\\#{path}"
        @handle = @k.CreateFileW("#{name}\0".encode("UTF-16LE"), GENERIC_READ_WRITE, 0, nil, OPEN_EXISTING, 0, nil)
        if @handle.to_i == (1 << (8 * Fiddle::SIZEOF_VOIDP)) - 1 || @handle.to_i == -1
          raise Error, "Cannot open #{path} (error #{@k.GetLastError})"
        end

        @dtr = @rts = false
        @read_timeout = nil
        self.baud = baud
      end

      def resettable? = true
      def usb_jtag_serial? = nil

      # The DCB also carries the DTR/RTS state, so a baud change keeps the lines as they are.
      def baud=(baud)
        @baud = baud
        dcb = "\0".b * 28
        dcb[0, 4] = [28].pack("V")
        check(@k.GetCommState(@handle, dcb), "GetCommState")
        flags = 0x0001 # fBinary; no parity check, no flow control
        flags |= 0x0010 if @dtr # fDtrControl = DTR_CONTROL_ENABLE
        flags |= 0x1000 if @rts # fRtsControl = RTS_CONTROL_ENABLE
        dcb[4, 4] = [baud].pack("V")
        dcb[8, 4] = [flags].pack("V")
        dcb[18, 3] = [8, 0, 0].pack("C3") # 8 data bits, no parity, 1 stop bit
        check(@k.SetCommState(@handle, dcb), "SetCommState")
      end

      def read(max, timeout)
        ms = (timeout * 1000).ceil
        if @read_timeout != ms
          # Return as soon as any byte is there, or after +ms+ when nothing comes.
          timeouts = ms.zero? ? [MAXDWORD, 0, 0, 0, 0] : [MAXDWORD, MAXDWORD, ms, 0, 0]
          check(@k.SetCommTimeouts(@handle, timeouts.pack("V5")), "SetCommTimeouts")
          @read_timeout = ms
        end
        buf = "\0".b * max
        count = [0].pack("V")
        raise Disconnected, "#{@path}: ReadFile failed" if @k.ReadFile(@handle, buf, max, count, nil).zero?

        buf.byteslice(0, count.unpack1("V"))
      end

      def write(bytes)
        bytes = bytes.b
        until bytes.empty?
          count = [0].pack("V")
          raise Disconnected, "#{@path}: WriteFile failed" if @k.WriteFile(@handle, bytes, bytes.bytesize, count, nil).zero?

          bytes = bytes.byteslice(count.unpack1("V")..)
        end
      end

      # DTR first: usbser.sys only passes a DTR change on together with the next RTS one.
      def set_lines(dtr: nil, rts: nil)
        unless dtr.nil?
          @dtr = dtr
          @k.EscapeCommFunction(@handle, dtr ? SETDTR : CLRDTR)
        end
        return if rts.nil? && dtr.nil?

        @rts = rts unless rts.nil?
        @k.EscapeCommFunction(@handle, @rts ? SETRTS : CLRRTS)
      end

      def discard_input
        @k.PurgeComm(@handle, PURGE_RXCLEAR)
      end

      def close
        @k.CloseHandle(@handle) if @handle
        @handle = nil
      end

      private

      def check(result, what)
        raise Error, "#{what} failed on #{@path} (error #{@k.GetLastError})" if result.zero?
      end
    end
  end
end
