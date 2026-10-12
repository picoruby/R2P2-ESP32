# frozen_string_literal: true

require "digest/md5"
require "json"
require "zlib"

module EspFlash
  # Writes images to the SPI flash through the serial bootloader in the chip's ROM (the protocol esptool
  # speaks: https://docs.espressif.com/projects/esptool/en/latest/esp32/advanced-topics/serial-protocol.html).
  #
  # Once connected, the loader uploads the flasher stub of esp-flasher-stub (stub/, MIT or Apache-2.0) into
  # the chip's RAM and talks to that instead, as esptool does: it takes 16 KB blocks and erases as it
  # writes, which is much faster than the ROM loader. With stub: false (or when there is no stub for the
  # chip, or over TCP to QEMU, which cannot run it) the ROM loader does the work itself.
  # Images are written as they are; their headers are not patched for flash mode/size/frequency, since
  # ESP-IDF builds them with the values from sdkconfig (the ones flasher_args.json gives to esptool).
  class Loader
    FLASH_BEGIN = 0x02
    FLASH_DATA = 0x03
    FLASH_END = 0x04
    MEM_BEGIN = 0x05
    MEM_END = 0x06
    MEM_DATA = 0x07
    SYNC = 0x08
    WRITE_REG = 0x09
    READ_REG = 0x0a
    SPI_SET_PARAMS = 0x0b
    SPI_ATTACH = 0x0d
    CHANGE_BAUDRATE = 0x0f
    FLASH_DEFL_BEGIN = 0x10
    FLASH_DEFL_DATA = 0x11
    FLASH_DEFL_END = 0x12
    SPI_FLASH_MD5 = 0x13
    GET_SECURITY_INFO = 0x14

    ROM_BAUD = 115_200
    BLOCK_SIZE = 0x400 # the ROM loader's FLASH_WRITE_SIZE
    STUB_BLOCK_SIZE = 0x4000 # the stub's
    RAM_BLOCK_SIZE = 0x1800
    STUB_DIR = File.join(__dir__, "stub")
    CHECKSUM_SEED = 0xef
    CHIP_DETECT_MAGIC_REG = 0x40001000

    # Chip => [image chip id (GET_SECURITY_INFO), values of CHIP_DETECT_MAGIC_REG]
    CHIPS = {
      "esp32" => [0, [0x00f01d83]],
      "esp32s2" => [2, [0x000007c6]],
      "esp32c3" => [5, [0x6921506f, 0x1b31506f, 0x4881606f, 0x4361606f]],
      "esp32s3" => [9, [0x9]],
      "esp32c2" => [12, [0x6f51306f, 0x7c41a06f]],
      "esp32c6" => [13, [0x2ce0806f]],
      "esp32h2" => [16, [0xd7b73e80]],
      "esp32p4" => [18, [0x0, 0x0addbad0]],
      "esp32c5" => [23, []],
    }.freeze

    # Chip => [RTC WDT write protect, RTC WDT config0, SWD write protect, SWD config, SWD auto feed bit, SWD key].
    # Over the USB-Serial/JTAG nothing feeds these watchdogs while the chip waits in the download mode, and
    # they can reset it in the middle of flashing; esptool disables them the same way.
    WATCHDOGS = {
      "esp32c3" => [0x600080a8, 0x60008090, 0x600080b0, 0x600080ac, 1 << 31, 0x8f1d312a],
      "esp32s3" => [0x600080b0, 0x60008098, 0x600080b8, 0x600080b4, 1 << 31, 0x8f1d312a],
      "esp32c6" => [0x600b1c18, 0x600b1c00, 0x600b1c20, 0x600b1c1c, 1 << 18, 0x50d83aa1],
      "esp32h2" => [0x600b1c1c, 0x600b1c00, 0x600b1c24, 0x600b1c20, 1 << 18, 0x50d83aa1],
      "esp32p4" => [0x50116018, 0x50116000, 0x50116020, 0x5011601c, 1 << 18, 0x50d83aa1],
    }.freeze
    WDT_KEY = 0x50d83aa1

    ROM_ERRORS = {
      0x05 => "received message is invalid",
      0x06 => "failed to act on received message",
      0x07 => "invalid CRC in message",
      0x08 => "flash write error",
      0x09 => "flash read error",
      0x0a => "flash read length error",
      0x0b => "deflate error",
    }.freeze

    attr_reader :chip

    # Opens +port+, resets the chip into its ROM loader, syncs with it and starts the flasher stub (unless
    # +stub+ is false). +chip+ (e.g. "esp32s3") is what the image was built for; flashing another chip is
    # refused. +log+ receives progress messages.
    def self.open(port, chip:, baud: 460_800, flash_size: nil, reset: true, stub: true, log: $stdout)
      loader = new(SerialPort.open(port, ROM_BAUD), log: log)
      begin
        loader.connect(reset: reset)
        loader.check_chip(chip)
        loader.disable_watchdogs
        loader.run_stub if stub
        loader.attach_flash(flash_size)
        loader.change_baud(baud) if baud && baud != ROM_BAUD
        loader
      rescue StandardError
        loader.close
        raise
      end
    end

    def initialize(port, log: $stdout)
      @port = port
      @log = log
      @buffer = "".b
    end

    # Resets into the ROM loader (when the port can) and syncs, trying the reset sequences esptool uses.
    def connect(reset: true, attempts: 7)
      @log.print "Connecting to #{@port.path}..."
      strategies = reset && @port.resettable? ? reset_strategies : [nil]
      attempts.times do |i|
        strategy = strategies[i % strategies.size]
        send(*strategy) if strategy
        @port.discard_input
        @buffer.clear
        if sync
          @log.puts " connected."
          return
        end
        @log.print "."
      end
      @log.puts
      raise Error, "Failed to connect to the chip on #{@port.path}. " \
                   "Hold BOOT (GPIO0) while pressing RESET to enter the download mode, and try again."
    end

    # The chip the ROM reports, checked against what the image was built for.
    def check_chip(expected)
      @chip = detect_chip
      @log.puts "Chip is #{@chip || "unknown"}"
      return if expected.nil? || @chip.nil? || @chip == expected

      raise Error, "This image is for #{expected}, but the connected chip is #{@chip}."
    end

    def disable_watchdogs
      return unless @port.usb_jtag_serial? != false && (regs = WATCHDOGS[@chip])

      wdt_protect, wdt_config, swd_protect, swd_config, swd_auto_feed, swd_key = regs
      write_reg(wdt_protect, WDT_KEY)
      write_reg(wdt_config, 0)
      write_reg(wdt_protect, 0)
      write_reg(swd_protect, swd_key)
      write_reg(swd_config, read_reg(swd_config) | swd_auto_feed)
      write_reg(swd_protect, 0)
    end

    # Uploads the flasher stub for the chip into its RAM and runs it. Nothing happens when there is no stub
    # for the chip, or the port is a TCP socket (QEMU, which cannot run the stub).
    def run_stub
      return if @stub || !@port.resettable? || @chip.nil?

      file = File.join(STUB_DIR, "#{@chip}.json")
      return unless File.exist?(file)

      stub = JSON.parse(File.read(file))
      %w[text data].each do |segment|
        next unless stub[segment]

        upload_to_ram(stub[segment].unpack1("m"), stub["#{segment}_start"])
      end
      # The response to MEM_END may be lost as the stub takes over the UART; its greeting is what counts.
      send_packet(MEM_END, [0, stub["entry"]].pack("VV"))
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      loop do
        break if read_packet(deadline) == "OHAI"
      end
      @stub = true
      @log.puts "Stub flasher running."
    rescue TimeoutError
      raise Error, "The flasher stub did not start. Try again with NO_STUB=1 (writes through the ROM loader)."
    end

    # Enables the default SPI flash pins and tells the flash geometry.
    def attach_flash(flash_size)
      # The ROM takes an extra "is legacy" word
      command(SPI_ATTACH, @stub ? [0].pack("V") : [0, 0].pack("VV"))
      size = flash_size || 16 * 1024 * 1024
      command(SPI_SET_PARAMS, [0, size, 64 * 1024, 4 * 1024, 256, 0xffff].pack("V6"))
    end

    def change_baud(baud)
      return unless @port.resettable? # a TCP socket has no baud rate

      # The stub also takes the current baud rate
      command(CHANGE_BAUDRATE, [baud, @stub ? ROM_BAUD : 0].pack("VV"))
      @port.baud = baud
      sleep 0.05
      @port.discard_input
      @buffer.clear
      @log.puts "Changed baud rate to #{baud}"
    end

    # Writes +data+ at +offset+ compressed, then checks it against the MD5 the chip computes.
    def write_flash(offset, data, name: nil)
      data = data.b
      data += "\xff".b * (-data.bytesize % 4)
      compressed = Zlib::Deflate.deflate(data, Zlib::BEST_COMPRESSION)
      block_size = @stub ? STUB_BLOCK_SIZE : BLOCK_SIZE
      blocks = (compressed.bytesize + block_size - 1) / block_size
      label = format("0x%08x", offset)
      label += " (#{name})" if name

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if @stub
        # The stub erases as it writes
        command(FLASH_DEFL_BEGIN, [data.bytesize, blocks, block_size, offset, 0].pack("V5"))
      else
        # The ROM erases the whole region first
        erase_size = (data.bytesize + block_size - 1) / block_size * block_size
        params = [erase_size, blocks, block_size, offset].pack("V4")
        params += [0].pack("V") if encrypted_flag?
        command(FLASH_DEFL_BEGIN, params, timeout: timeout_per_mb(30, erase_size))
      end

      blocks.times do |seq|
        chunk = compressed.byteslice(seq * block_size, block_size)
        command(FLASH_DEFL_DATA, [chunk.bytesize, seq, 0, 0].pack("V4") + chunk,
                checksum: checksum(chunk), timeout: 10)
        progress(label, seq + 1, blocks)
      end
      # The stub acknowledges a block before writing it; this returns once the last one is written.
      command(FLASH_DEFL_END, [1].pack("V"), timeout: 10) if @stub
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      @log.puts format("%sWrote %d bytes (%d compressed) at %s in %.1f s", tty? ? "\r" : "", data.bytesize,
                       compressed.bytesize, label, elapsed)

      verify(offset, data)
    end

    # Resets the chip into the application (the ROM loader is left as it is when the port cannot reset).
    def hard_reset
      return unless @port.resettable?

      @log.puts "Hard resetting via RTS pin..."
      EspFlash.hard_reset(@port)
    end

    def close
      @port.close
    end

    private

    def reset_strategies
      usb_jtag = @port.usb_jtag_serial?
      return [[:usb_jtag_reset]] if usb_jtag

      tight = @port.is_a?(SerialPort::PosixPort)
      list = [0.05, 0.55].flat_map do |delay|
        [([:tight_reset, delay] if tight), [:classic_reset, delay]].compact
      end
      usb_jtag.nil? ? list + [[:usb_jtag_reset]] : list
    end

    # The reset sequences of esptool (esptool/reset.py). On a board's auto-reset circuit DTR drives
    # GPIO0 and RTS drives EN; "true" asserts a line, which pulls the pin low.
    def classic_reset(delay)
      @port.set_lines(dtr: false)
      @port.set_lines(rts: true) # EN low: in reset
      sleep 0.1
      @port.set_lines(dtr: true) # GPIO0 low
      @port.set_lines(rts: false) # EN high: out of reset, into the download mode
      sleep delay
      @port.set_lines(dtr: false)
    end

    # Like classic_reset, with both lines changed at once (some USB-UART bridges need that).
    def tight_reset(delay)
      @port.set_lines(dtr: false, rts: false)
      @port.set_lines(dtr: true, rts: true)
      @port.set_lines(dtr: false, rts: true)
      sleep 0.1
      @port.set_lines(dtr: true, rts: false)
      sleep delay
      @port.set_lines(dtr: false, rts: false)
      @port.set_lines(dtr: false)
    end

    # For the USB-Serial/JTAG controller, which must go through (1, 1) instead of (0, 0).
    def usb_jtag_reset
      @port.set_lines(rts: false)
      @port.set_lines(dtr: false)
      sleep 0.1
      @port.set_lines(dtr: true)
      @port.set_lines(rts: false)
      sleep 0.1
      @port.set_lines(rts: true)
      @port.set_lines(dtr: false)
      @port.set_lines(rts: true)
      sleep 0.1
      @port.set_lines(dtr: false)
      @port.set_lines(rts: false)
    end

    def sync
      payload = [0x07, 0x07, 0x12, 0x20].pack("C4") + ("\x55".b * 32)
      5.times do
        begin
          command(SYNC, payload, timeout: 0.1)
          # The ROM answers a SYNC several times; drop the rest.
          sleep 0.05
          @port.discard_input
          @buffer.clear
          return true
        rescue Error
          next
        end
      end
      false
    end

    def detect_chip
      info = command(GET_SECURITY_INFO, "", timeout: 1)
      if info.bytesize >= 20
        chip_id = info.byteslice(12, 4).unpack1("V")
        found = CHIPS.find { |_name, (id, _magic)| id == chip_id }
        return found.first if found
      end
      magic_chip
    rescue Error
      magic_chip # the ESP32 ROM does not know GET_SECURITY_INFO
    end

    def magic_chip
      magic = read_reg(CHIP_DETECT_MAGIC_REG)
      CHIPS.find { |_name, (_id, values)| values.include?(magic) }&.first
    end

    def read_reg(address)
      command(READ_REG, [address].pack("V"), want_value: true)
    end

    def write_reg(address, value)
      command(WRITE_REG, [address, value, 0xffffffff, 0].pack("V4"))
    end

    def upload_to_ram(data, address)
      blocks = (data.bytesize + RAM_BLOCK_SIZE - 1) / RAM_BLOCK_SIZE
      command(MEM_BEGIN, [data.bytesize, blocks, RAM_BLOCK_SIZE, address].pack("V4"))
      blocks.times do |seq|
        chunk = data.byteslice(seq * RAM_BLOCK_SIZE, RAM_BLOCK_SIZE)
        command(MEM_DATA, [chunk.bytesize, seq, 0, 0].pack("V4") + chunk, checksum: checksum(chunk))
      end
    end

    # The ROM loader ends every response with 4 status bytes, the stub with 2.
    def status_bytes
      @stub ? 2 : 4
    end

    def encrypted_flag?
      # Every ROM loader after the ESP32's takes an extra "encrypted" word in FLASH_(DEFL_)BEGIN.
      @chip != "esp32"
    end

    def verify(offset, data)
      response = command(SPI_FLASH_MD5, [offset, data.bytesize, 0, 0].pack("V4"),
                         timeout: timeout_per_mb(8, data.bytesize))
      # The stub answers with the 16 bytes of the MD5, the ROM with them in hex
      actual = @stub ? response.byteslice(0, 16).unpack1("H*") : response.byteslice(0, 32).downcase
      expected = Digest::MD5.hexdigest(data)
      raise Error, format("Verification failed at 0x%08x: flash has MD5 %s, expected %s", offset, actual, expected) \
        unless actual == expected

      @log.puts "Hash of data verified."
    end

    def checksum(data)
      data.each_byte.reduce(CHECKSUM_SEED) { |sum, byte| sum ^ byte }
    end

    def timeout_per_mb(seconds, size)
      [3.0, seconds * size / 1_000_000.0].max
    end

    def tty?
      @log.respond_to?(:tty?) && @log.tty?
    end

    def progress(label, done, total)
      return unless tty?
      return unless done == total || (done % 16).zero?

      @log.print format("\rWriting at %s... (%d %%)", label, done * 100 / total)
    end

    # Sends a command and returns the data of its response (or its 32-bit value when +want_value+).
    def command(op, data, checksum: 0, timeout: 3, want_value: false)
      send_packet(op, data, checksum)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        packet = read_packet(deadline)
        next if packet.bytesize < 8

        direction, resp_op, _size, value = packet.unpack("CCvV")
        next unless direction == 0x01 && resp_op == op

        body = packet.byteslice(8..)
        status = body.byteslice(-status_bytes, status_bytes) if body.bytesize >= status_bytes
        raise Error, format("Command 0x%02x: no status in the response", op) unless status
        if status.getbyte(0) != 0
          code = status.getbyte(1)
          raise Error, format("Command 0x%02x failed: %s (0x%02x)", op, ROM_ERRORS.fetch(code, "unknown error"), code)
        end

        return want_value ? value : body.byteslice(0, body.bytesize - status_bytes)
      end
    end

    def send_packet(op, data, checksum = 0)
      @port.write(slip_encode([0x00, op, data.bytesize, checksum].pack("CCvV") + data))
    end

    def slip_encode(packet)
      "\xc0".b + packet.b.gsub("\xdb".b, "\xdb\xdd".b).gsub("\xc0".b, "\xdb\xdc".b) + "\xc0".b
    end

    # The next SLIP frame, skipping anything outside frames (such as the boot log).
    def read_packet(deadline)
      loop do
        if (start = @buffer.index("\xc0".b))
          if (stop = @buffer.index("\xc0".b, start + 1))
            frame = @buffer.byteslice(start + 1, stop - start - 1)
            @buffer = @buffer.byteslice(stop..) # the closing 0xc0 may open the next frame
            next if frame.empty?

            return frame.gsub(/\xdb[\xdc\xdd]/n) { |escape| escape.getbyte(1) == 0xdc ? "\xc0".b : "\xdb".b }
          end
          @buffer = @buffer.byteslice(start..)
        else
          @buffer.clear
        end

        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise TimeoutError, "Timed out waiting for a response from the chip" if remaining <= 0

        @buffer << @port.read(4096, remaining)
      end
    end
  end
end
