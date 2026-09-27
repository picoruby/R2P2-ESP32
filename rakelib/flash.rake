require "json"
require "rbconfig"
require "open-uri"
require "tmpdir"

# Bumping this also bumps the binary `rake setup_espflash` downloads.
ESPFLASH_VERSION = "4.6.0"
ESPFLASH_DIR = File.join(R2P2_ESP32_ROOT, ".tools")
ESPFLASH_BIN = File.join(ESPFLASH_DIR, Gem.win_platform? ? "espflash.exe" : "espflash")

# Read from build/project_description.json rather than hardcoding, so this tracks whatever
# target/VM the build was last configured for.
def build_project_description
  JSON.parse(File.read(File.join(R2P2_ESP32_ROOT, "build", "project_description.json")))
end

def on_path(name)
  ENV["PATH"].split(File::PATH_SEPARATOR)
             .map { |dir| File.join(dir, name) }
             .find { |path| File.file?(path) && File.executable?(path) }
end

# esptool.py (or its newer `esptool` entry point) already on PATH -- e.g. from
# `pip install esptool`. nil if not found, so callers fall back to espflash.
def find_esptool
  on_path("esptool.py") || on_path("esptool")
end

# esp-idf-monitor already on PATH, either as its own script or as a python3 module. nil if
# not found, so callers fall back to espflash.
def find_idf_monitor
  return "idf-monitor" if on_path("idf-monitor")
  return "python3 -m esp_idf_monitor" if on_path("python3") &&
    system("python3 -c 'import esp_idf_monitor'", out: File::NULL, err: File::NULL)

  nil
end

# This host's OS/CPU as an espflash release asset target (`espflash-<target>.zip` at
# https://github.com/esp-rs/espflash/releases), or nil if espflash doesn't publish one.
def espflash_release_target
  cpu =
    case RbConfig::CONFIG["host_cpu"]
    when /x86_64|amd64/ then "x86_64"
    when /aarch64|arm64/ then "aarch64"
    when /^arm/ then "armv7"
    end
  return nil unless cpu

  case RbConfig::CONFIG["host_os"]
  when /darwin/
    "#{cpu}-apple-darwin" if %w[x86_64 aarch64].include?(cpu)
  when /linux/
    case cpu
    when "x86_64", "aarch64" then "#{cpu}-unknown-linux-gnu"
    when "armv7" then "armv7-unknown-linux-gnueabihf"
    end
  when /mingw|mswin|windows/
    "x86_64-pc-windows-msvc" if cpu == "x86_64"
  end
end

# Downloads the prebuilt espflash binary into ESPFLASH_DIR. Returns false (never raises) on
# any failure -- unsupported host/CPU, no network, etc. -- so callers can fall back.
def download_espflash
  target = espflash_release_target
  return false unless target

  asset = "espflash-#{target}.zip"
  url = "https://github.com/esp-rs/espflash/releases/download/v#{ESPFLASH_VERSION}/#{asset}"

  puts "Downloading #{url}"
  FileUtils.mkdir_p(ESPFLASH_DIR)
  Dir.mktmpdir do |tmp|
    zip_path = File.join(tmp, asset)
    URI.open(url, "rb") { |remote| File.binwrite(zip_path, remote.read) }

    if Gem.win_platform?
      sh "powershell", "-NoProfile", "-Command",
         "Expand-Archive -Force -Path '#{zip_path}' -DestinationPath '#{tmp}'"
    else
      sh "unzip", "-o", "-q", zip_path, "-d", tmp
    end

    FileUtils.cp(File.join(tmp, File.basename(ESPFLASH_BIN)), ESPFLASH_BIN)
    File.chmod(0755, ESPFLASH_BIN) unless Gem.win_platform?
  end
  true
rescue StandardError => e
  warn "Warning: failed to download espflash (#{e.message})"
  false
end

# Returns a path to an espflash binary -- already downloaded, already on PATH, or freshly
# downloaded -- or nil (never raises) if none is available.
def find_espflash
  return ESPFLASH_BIN if File.executable?(ESPFLASH_BIN)

  found = on_path(Gem.win_platform? ? "espflash.exe" : "espflash")
  return found if found

  ESPFLASH_BIN if download_espflash
end

desc "Report which flashing tool `rake flash`/`rake monitor` will use (and download espflash if needed)"
task :setup_espflash do
  if find_esptool
    puts "esptool.py is available; `rake flash` will use it (skipping espflash)."
  elsif (espflash = find_espflash)
    puts "espflash is available (#{espflash}); `rake flash` will use it."
  else
    puts "Neither esptool.py nor espflash could be found or downloaded for this host."
  end
end

# ENV['PORT'] overrides the serial port; otherwise the flashing tool auto-detects it.
# Prefers an esptool.py already on the host (e.g. from a pre-existing `pip install esptool`)
# to avoid changing behavior for hosts already set up that way; otherwise uses espflash,
# downloading it if neither is already available.
desc "Flash the built firmware to ESP32, preferring an existing esptool.py, otherwise espflash"
task :flash do
  chip = build_project_description["target"]

  FileUtils.cd(File.join(R2P2_ESP32_ROOT, "build")) do
    if find_esptool
      port = ENV["PORT"] ? "--port #{ENV['PORT']}" : ""
      sh "esptool.py --chip #{chip} #{port} " \
         "-b 460800 --before default_reset --after hard_reset write_flash @flash_args"
    else
      espflash = find_espflash or abort "espflash could not be found or downloaded, and no esptool.py is on PATH."
      port_args = ENV["PORT"] ? ["--port", ENV["PORT"]] : []
      flash_files = JSON.parse(File.read("flasher_args.json"))["flash_files"]
      flash_files.sort_by { |addr, _file| Integer(addr, 16) }.each do |addr, file|
        sh espflash, "write-bin", addr, file,
           "--chip", chip, "--baud", "460800", "--non-interactive", *port_args
      end
    end
  end
end

desc "Erase factory partition and flash firmware binary"
task :flash_factory do
  if find_esptool
    sh "esptool.py -b 460800 erase_region 0x10000 0x200000"
    sh "esptool.py -b 460800 write_flash 0x10000 build/R2P2-ESP32.bin"
  else
    espflash = find_espflash or abort "espflash could not be found or downloaded, and no esptool.py is on PATH."
    sh espflash, "erase-region", "0x10000", "0x200000", "--non-interactive"
    sh espflash, "write-bin", "0x10000", "build/R2P2-ESP32.bin", "--non-interactive"
  end
end

desc "Erase storage partition and flash storage binary"
task :flash_storage do
  if find_esptool
    sh "esptool.py -b 460800 erase_region 0x210000 0x100000"
    sh "esptool.py -b 460800 write_flash 0x210000 build/storage.bin"
  else
    espflash = find_espflash or abort "espflash could not be found or downloaded, and no esptool.py is on PATH."
    sh espflash, "erase-region", "0x210000", "0x100000", "--non-interactive"
    sh espflash, "write-bin", "0x210000", "build/storage.bin", "--non-interactive"
  end
end

desc "Monitor ESP32 serial output, preferring an existing esp-idf-monitor, otherwise espflash"
task :monitor do
  desc_json = build_project_description
  port = ENV["PORT"] ? "--port #{ENV['PORT']}" : ""

  if (monitor_cmd = find_idf_monitor)
    sh "#{monitor_cmd} #{port} -b #{desc_json['monitor_baud']} build/#{desc_json['app_elf']}"
  else
    espflash = find_espflash or abort "espflash could not be found or downloaded, and no esp-idf-monitor is on PATH."
    port_args = ENV["PORT"] ? ["--port", ENV["PORT"]] : []
    sh espflash, "monitor",
       "--chip", desc_json["target"],
       "--monitor-baud", desc_json["monitor_baud"].to_s,
       "--elf", File.join("build", desc_json["app_elf"]),
       *port_args
  end
end
