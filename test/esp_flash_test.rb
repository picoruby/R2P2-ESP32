# frozen_string_literal: true

# ruby -Ilib test/esp_flash_test.rb
require "minitest/autorun"
require "digest/md5"
require "json"
require "socket"
require "stringio"
require "zlib"
require "esp_flash"

# A port with a chip's ROM loader behind it, enough of it for EspFlash::Loader, and the flasher stub once
# that is loaded into RAM.
class FakeRomPort
  attr_reader :flash, :baud, :ops, :ram, :registers, :block_sizes
  attr_accessor :corrupt_md5

  def initialize(chip_id: nil, magic: 0, usb_jtag: false)
    @chip_id = chip_id # nil: GET_SECURITY_INFO is unknown, as on the ESP32
    @magic = magic
    @usb_jtag = usb_jtag
    @ram = {}
    @registers = {}
    @block_sizes = []
    @stub = false
    @flash = "\xff".b * (4 << 20)
    @rx = "".b
    @tx = "".b
    @ops = []
  end

  def path = "fake"
  def encrypted_word? = @encrypted_word
  def resettable? = true
  def usb_jtag_serial? = @usb_jtag
  def stub? = @stub
  def set_lines(dtr: nil, rts: nil); end
  def discard_input = @rx.clear
  def close; end

  def baud=(baud)
    @baud = baud
  end

  def read(max, _timeout)
    @rx.slice!(0, max)
  end

  def write(bytes)
    @tx << bytes
    while (start = @tx.index("\xc0".b)) && (stop = @tx.index("\xc0".b, start + 1))
      frame = @tx.byteslice(start + 1, stop - start - 1)
      @tx = @tx.byteslice(stop + 1..)
      handle(frame.gsub(/\xdb[\xdc\xdd]/n) { |e| e.getbyte(1) == 0xdc ? "\xc0".b : "\xdb".b })
    end
  end

  private

  def handle(packet)
    _dir, op, size, checksum = packet.unpack("CCvV")
    data = packet.byteslice(8, size)
    @ops << op
    case op
    when 0x08 then 3.times { reply(op) } # SYNC: answered more than once
    when 0x0a then reply(op, value: @registers.fetch(data.unpack1("V"), @magic))
    when 0x09
      address, value = data.unpack("VV")
      @registers[address] = value
      reply(op)
    when 0x05
      _size, _blocks, _block_size, @mem_address = data.unpack("V4")
      @ram[@mem_address] = "".b
      reply(op)
    when 0x07
      len, = data.unpack("V")
      chunk = data.byteslice(16, len)
      return reply(op, error: 0x07) unless checksum == chunk.each_byte.reduce(0xef) { |s, b| s ^ b }

      @ram[@mem_address] << chunk
      reply(op)
    when 0x06
      reply(op)
      @stub = true
      @rx << "\xc0OHAI\xc0".b
    when 0x14
      return reply(op, error: 0x05) unless @chip_id

      reply(op, [0, 0, 0, 0, 0, 0, 0, 0, 0, @chip_id, 0].pack("VC8VV"))
    when 0x0b, 0x0d, 0x0f then reply(op)
    when 0x10
      @write_size, @blocks, block_size, @offset = data.unpack("V4")
      @block_sizes << block_size
      @encrypted_word = data.bytesize == 20
      @seq = 0
      @inflater = Zlib::Inflate.new
      @pos = @offset
      reply(op)
    when 0x11
      len, seq = data.unpack("VV")
      chunk = data.byteslice(16, len)
      return reply(op, error: 0x07) unless checksum == chunk.each_byte.reduce(0xef) { |s, b| s ^ b }
      return reply(op, error: 0x05) unless seq == @seq

      @seq += 1
      out = @inflater.inflate(chunk)
      @flash[@pos, out.bytesize] = out
      @pos += out.bytesize
      reply(op)
    when 0x13
      addr, len = data.unpack("VV")
      md5 = Digest::MD5.hexdigest(@flash.byteslice(addr, len))
      md5 = md5.reverse if corrupt_md5
      reply(op, @stub ? [md5].pack("H*") : md5) # the stub answers with the bytes, the ROM in hex
    when 0x12
      return reply(op, error: 0x05) unless @stub

      reply(op)
    else
      reply(op, error: 0x05)
    end
  end

  def reply(op, body = "".b, value: 0, error: nil)
    status = error ? [1, error, 0, 0].pack("C4") : "\0\0\0\0".b
    status = status.byteslice(0, 2) if @stub # the stub sends 2 status bytes
    packet = [0x01, op, body.bytesize + 4, value].pack("CCvV") + body + status
    @rx << "\xc0".b + packet.gsub("\xdb".b, "\xdb\xdd".b).gsub("\xc0".b, "\xdb\xdc".b) + "\xc0".b
  end
end

class LoaderTest < Minitest::Test
  def loader(port, chip)
    loader = EspFlash::Loader.new(port, log: StringIO.new)
    loader.connect
    loader.check_chip(chip)
    loader.attach_flash(4 << 20)
    loader.change_baud(460_800)
    loader
  end

  def test_writes_and_verifies_on_esp32s3
    port = FakeRomPort.new(chip_id: 9, magic: 0x9)
    data = Random.new(1).bytes(70_000) # includes 0xc0/0xdb bytes, which SLIP has to escape
    loader(port, "esp32s3").write_flash(0x10000, data)

    assert_equal data, port.flash.byteslice(0x10000, data.bytesize)
    assert_equal "\xff\xff".b, port.flash.byteslice(0x10000 + data.bytesize, 2) # padded to 4 bytes with 0xff
    assert port.encrypted_word?
    assert_equal 460_800, port.baud
  end

  def test_detects_esp32_by_magic_and_omits_encrypted_word
    port = FakeRomPort.new(magic: 0x00f01d83)
    l = loader(port, "esp32")
    assert_equal "esp32", l.chip
    l.write_flash(0x1000, "abcd")
    refute port.encrypted_word?
    assert_equal "abcd", port.flash.byteslice(0x1000, 4)
  end

  def test_refuses_another_chip
    port = FakeRomPort.new(chip_id: 5)
    error = assert_raises(EspFlash::Error) { loader(port, "esp32s3") }
    assert_match(/for esp32s3.*esp32c3/, error.message)
  end

  def test_writes_through_the_stub
    port = FakeRomPort.new(chip_id: 9, usb_jtag: true)
    l = EspFlash::Loader.new(port, log: StringIO.new)
    l.connect
    l.check_chip("esp32s3")
    l.disable_watchdogs
    l.run_stub
    l.attach_flash(4 << 20)
    l.change_baud(460_800)
    data = Random.new(2).bytes(100_000)
    l.write_flash(0x10000, data)

    assert port.stub?
    stub = JSON.parse(File.read(File.join(EspFlash::Loader::STUB_DIR, "esp32s3.json")))
    assert_equal stub["text"].unpack1("m"), port.ram[stub["text_start"]]
    assert_equal stub["data"].unpack1("m"), port.ram[stub["data_start"]]
    assert_equal 0, port.registers[0x60008098] # the RTC WDT is off
    assert_equal [0x4000], port.block_sizes
    assert_equal data, port.flash.byteslice(0x10000, data.bytesize)
    assert_equal 0x12, port.ops.last(2).first # FLASH_DEFL_END before the MD5
  end

  def test_md5_mismatch_fails
    port = FakeRomPort.new(chip_id: 9)
    l = loader(port, "esp32s3")
    port.corrupt_md5 = true
    assert_raises(EspFlash::Error) { l.write_flash(0, "x" * 100) }
  end
end

class EspFlashTest < Minitest::Test
  def test_merge_images
    merged = EspFlash.merge_images({ 4 => "bb", 0 => "a" }, size: 8)
    assert_equal "a\xff\xff\xffbb\xff\xff".b, merged
    assert_raises(EspFlash::Error) { EspFlash.merge_images({ 0 => "aaa", 2 => "b" }) }
    assert_raises(EspFlash::Error) { EspFlash.merge_images({ 0 => "aaa" }, size: 2) }
  end

  def test_parse_size
    assert_equal 4 << 20, EspFlash.parse_size("4MB")
    assert_equal 512 << 10, EspFlash.parse_size("512KB")
    assert_raises(EspFlash::Error) { EspFlash.parse_size("detect") }
  end

  def test_resolve_prefers_the_given_port
    assert_equal "/dev/ttyX", EspFlash::SerialPort.resolve("/dev/ttyX")
  end
end

class PosixPortTest < Minitest::Test
  # A pseudo terminal stands in for a USB serial device (it has no modem lines, though).
  def test_raw_bytes_at_any_baud
    skip "POSIX only" if Gem.win_platform?
    require "pty"
    controller, device = PTY.open
    port = EspFlash::SerialPort::PosixPort.new(device.path, 115_200)
    port.baud = 460_800

    port.write("\xc0\x03\n".b)
    assert_equal "\xc0\x03\n".b, controller.readpartial(100) # no "\n" => "\r\n"
    controller.write("\x03\r\x11".b)
    assert_equal "\x03\r\x11".b, port.read(100, 1) # no signal, CR or XON handling
    assert_equal "".b, port.read(100, 0.1)
  ensure
    port&.close
    controller&.close
    device&.close
  end
end

class MonitorTest < Minitest::Test
  # Keys go to the device byte for byte (terminal replies included) except Ctrl-] and the Ctrl-T menu.
  def test_forwards_input_verbatim
    server = TCPServer.new("127.0.0.1", 0)
    input_r, input_w = IO.pipe
    output = StringIO.new
    monitor = EspFlash::Monitor.new("socket://127.0.0.1:#{server.addr[1]}", baud: 115_200, reset: false,
                                                                            input: input_r, output: output)
    thread = Thread.new { monitor.run }
    device = server.accept
    device.write("\e[5n") # the shell asks the terminal for its status

    input_w.write("ls\r\e[0n\x03\x14\x14\x14\x08") # reply, Ctrl-C, Ctrl-T Ctrl-T (a literal Ctrl-T), help
    deadline = Time.now + 5
    sleep 0.05 until output.string.include?("\e[5n") || Time.now > deadline
    input_w.write("\x1d") # quit
    assert thread.join(5), "monitor did not quit on Ctrl-]"

    received = device.read # until the monitor closes the connection
    assert_equal "ls\r\e[0n\x03\x14".b, received
    assert_includes output.string, "\e[5n" # what the device sent reaches the terminal
  ensure
    server&.close
  end

  # On a terminal, "\n" returns to the start of the line, and ESP-IDF log lines are colored.
  def test_renders_for_a_terminal
    monitor = EspFlash::Monitor.new("x", baud: 115_200, output: StringIO.new, terminal: true)
    render = ->(data) { monitor.send(:render, data.b) }

    assert_equal "\e[0;32mI (12) boot: hi\e[0m\r\nplain\r\n", render.("I (12) boot: hi\r\nplain\nW (3")
    assert_equal "\e[0;33mW (34) x: y\e[0m\r\n$> ", render.("4) x: y\n$> ")
    assert_equal "abc\r\n", render.("abc\nE") # "E" may start a log line
    assert_equal "Error\r\n", render.("rror\n")
    assert_equal "\e[1;31mE (5) t: a", render.("E (5) t: a")
    assert_equal " b\e[0m\r\n", render.(" b\r\n")
  end
end
