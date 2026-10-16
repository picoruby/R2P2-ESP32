# frozen_string_literal: true

# Flashing and monitoring an ESP32-family chip from plain Ruby (no Python esptool / esp-idf-monitor, no
# espflash binary, no gem): used by rakelib/flash.rake and rakelib/qemu.rake.
module EspFlash
  class Error < StandardError; end
  class TimeoutError < Error; end
  class Disconnected < Error; end

  # Resets the chip into the application: EN pulsed through RTS with DTR (GPIO0) released, as esptool's
  # hard reset does. A USB-Serial/JTAG controller needs the longer waits; they don't hurt a UART bridge.
  def self.hard_reset(port)
    port.set_lines(dtr: false)
    port.set_lines(rts: true)
    sleep 0.2
    port.set_lines(rts: false)
    sleep 0.2
  end

  # Builds one flash image from { offset => file data }, filling the gaps (and up to +size+) with 0xff,
  # like `esptool merge_bin --fill-flash-size`.
  def self.merge_images(images, size: nil)
    merged = "".b
    images.sort_by { |offset, _data| offset }.each do |offset, data|
      raise Error, format("Image at 0x%x overlaps the previous one", offset) if offset < merged.bytesize

      merged << ("\xff".b * (offset - merged.bytesize)) << data.b
    end
    raise Error, "Images exceed the flash size (#{size} bytes)" if size && merged.bytesize > size

    merged << ("\xff".b * (size - merged.bytesize)) if size
    merged
  end

  # "4MB" (as in flasher_args.json) => bytes
  def self.parse_size(text)
    match = /\A(\d+)\s*([KM])B\z/i.match(text.to_s) or raise Error, "Unknown flash size: #{text.inspect}"

    Integer(match[1]) * (match[2].casecmp?("M") ? 1024 * 1024 : 1024)
  end
end

require_relative "esp_flash/serial_port"
require_relative "esp_flash/loader"
require_relative "esp_flash/monitor"
