require "json"
require "digest"
require_relative "../lib/esp_flash"

FLASH_BAUD = Integer(ENV.fetch("FLASH_BAUD", "460800"))
STORAGE_OFFSET = 0x210000
STORAGE_SIZE = 0x100000

# Read from build/project_description.json rather than hardcoding, so this tracks whatever
# target/VM the build was last configured for.
def build_project_description
  JSON.parse(File.read(File.join(R2P2_ESP32_ROOT, "build", "project_description.json")))
end

# Arguments selecting the serial port given by ENV['PORT'] (none when unset, so that the tool
# auto-detects it).
def port_args(option = "--port")
  ENV["PORT"] ? [option, ENV["PORT"]] : []
end

def on_path(name)
  ENV["PATH"].split(File::PATH_SEPARATOR)
             .map { |dir| File.join(dir, name) }
             .find { |path| File.file?(path) && File.executable?(path) }
end

# The serial port: ENV['PORT'], or the one connected board (asks when there are several).
def flash_port
  EspFlash::SerialPort.resolve(ENV["PORT"])
end

# Connects to the chip on +port+ in its ROM loader, yields the loader and resets the chip into the app.
# The tasks end with the message of an EspFlash::Error instead of a backtrace. NO_STUB=1 writes through the
# ROM loader instead of the flasher stub.
def with_loader(port)
  flash_size = EspFlash.parse_size(flasher_args.dig("flash_settings", "flash_size"))
  loader = EspFlash::Loader.open(port, chip: build_project_description["target"], baud: FLASH_BAUD,
                                       flash_size: flash_size, stub: ENV["NO_STUB"].to_s.empty?)
  yield loader
  loader.hard_reset
ensure
  loader&.close
end

def build_file(name)
  File.binread(File.join(R2P2_ESP32_ROOT, "build", name))
end

# What `rake flash` last wrote besides the app: the serial port and the digests of the other images
# (bootloader, partition table, storage), keyed by offset.
FLASHED_IMAGES_FILE = File.join(R2P2_ESP32_ROOT, "build", "flashed_images.json")

def flasher_args
  JSON.parse(File.read(File.join(R2P2_ESP32_ROOT, "build", "flasher_args.json")))
end

def non_app_image_digests
  args = flasher_args
  args["flash_files"].reject { |addr, _file| addr == args["app"]["offset"] }.to_h do |addr, file|
    [addr, Digest::SHA256.file(File.join(R2P2_ESP32_ROOT, "build", file)).hexdigest]
  end
end

def flashed_images
  JSON.parse(File.read(FLASHED_IMAGES_FILE))
rescue Errno::ENOENT, JSON::ParserError
  nil
end

# The app partition's image (the only one `rake flash` rewrites when nothing else changed).
def flash_app(loader)
  app = flasher_args["app"]
  loader.write_flash(Integer(app["offset"], 16), build_file(app["file"]), name: app["file"])
end

# PORT selects the serial port; otherwise the one connected board is used (with several, it asks).
#
# When the images other than the app are identical to what the last `rake flash` wrote to the same
# port, only the app is flashed, which also keeps the files on the device. FULL_FLASH=1 always
# flashes everything.
desc "Flash the built firmware to ESP32 (only the app if nothing else changed; FULL_FLASH=1 to flash everything)"
task :flash do
  port = flash_port
  current = { "port" => port, "images" => non_app_image_digests }

  if ENV["FULL_FLASH"].to_s.empty? && flashed_images == current
    puts "Bootloader, partition table and storage are unchanged since the last `rake flash`; " \
         "flashing the app only (FULL_FLASH=1 to flash everything)"
    with_loader(port) { |loader| flash_app(loader) }
    next
  end

  # Forget the previous record first so that a failed flash never leads to an app-only flash
  rm_f FLASHED_IMAGES_FILE
  with_loader(port) do |loader|
    flasher_args["flash_files"].sort_by { |addr, _file| Integer(addr, 16) }.each do |addr, file|
      loader.write_flash(Integer(addr, 16), build_file(file), name: file)
    end
  end
  File.write(FLASHED_IMAGES_FILE, JSON.pretty_generate(current))
rescue EspFlash::Error => e
  abort "Error: #{e.message}"
end

# Writing erases the sectors the image covers, and the bootloader ignores whatever is left after the image.
desc "Flash firmware binary to the factory partition"
task :flash_factory do
  with_loader(flash_port) { |loader| flash_app(loader) }
rescue EspFlash::Error => e
  abort "Error: #{e.message}"
end

# The image is padded with 0xff to the whole partition, which erases the rest of it.
desc "Erase storage partition and flash storage binary"
task :flash_storage do
  storage = build_file("storage.bin")
  abort "Error: storage.bin is larger than the storage partition" if storage.bytesize > STORAGE_SIZE

  with_loader(flash_port) do |loader|
    loader.write_flash(STORAGE_OFFSET, storage + ("\xff".b * (STORAGE_SIZE - storage.bytesize)), name: "storage.bin")
  end
  # Keep the record of `rake flash` in sync with what is now on the device
  if (record = flashed_images)
    record["images"][format("0x%x", STORAGE_OFFSET)] = Digest::SHA256.hexdigest(storage)
    File.write(FLASHED_IMAGES_FILE, JSON.pretty_generate(record))
  end
rescue EspFlash::Error => e
  abort "Error: #{e.message}"
end

# Resets the device first (NO_RESET=1 to attach to it as it is). PORT=socket://HOST:PORT connects to
# QEMU's UART instead (see `rake qemu_serve`).
desc "Monitor ESP32 serial output (quit with Ctrl-], reset with Ctrl-T Ctrl-R)"
task :monitor do
  desc_json = build_project_description
  EspFlash::Monitor.new(flash_port, baud: Integer(desc_json["monitor_baud"]), target: desc_json["target"],
                                    elf: File.join(R2P2_ESP32_ROOT, "build", desc_json["app_elf"]),
                                    reset: ENV["NO_RESET"].to_s.empty?).run
rescue EspFlash::Error => e
  abort "Error: #{e.message}"
end
