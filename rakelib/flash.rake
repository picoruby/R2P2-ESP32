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

# Maps this host's OS/CPU to the release asset espflash publishes at
# https://github.com/esp-rs/espflash/releases (each is a `espflash-<target>.zip`).
def espflash_release_target
  cpu =
    case RbConfig::CONFIG["host_cpu"]
    when /x86_64|amd64/ then "x86_64"
    when /aarch64|arm64/ then "aarch64"
    when /^arm/ then "armv7"
    else abort "espflash: no prebuilt binary for CPU architecture " \
               "`#{RbConfig::CONFIG['host_cpu']}`. Install espflash yourself " \
               "(https://github.com/esp-rs/espflash) and put it on PATH."
    end

  case RbConfig::CONFIG["host_os"]
  when /darwin/
    abort "espflash: no prebuilt binary for macOS/#{cpu}" unless %w[x86_64 aarch64].include?(cpu)
    "#{cpu}-apple-darwin"
  when /linux/
    case cpu
    when "x86_64", "aarch64" then "#{cpu}-unknown-linux-gnu"
    when "armv7" then "armv7-unknown-linux-gnueabihf"
    end
  when /mingw|mswin|windows/
    abort "espflash: no prebuilt binary for Windows/#{cpu}" unless cpu == "x86_64"
    "x86_64-pc-windows-msvc"
  else
    abort "espflash: no prebuilt binary for OS `#{RbConfig::CONFIG['host_os']}`. " \
          "Install espflash yourself (https://github.com/esp-rs/espflash) and put it on PATH."
  end
end

def download_espflash
  asset = "espflash-#{espflash_release_target}.zip"
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
end

desc "Download the espflash binary that `rake flash`/`rake monitor` use (no Rust/cargo install needed)"
task :setup_espflash do
  download_espflash unless File.executable?(ESPFLASH_BIN)
end

# ENV['PORT'] overrides the serial port; otherwise espflash auto-detects it.
desc "Flash the built firmware to ESP32 via espflash (no Python/ESP-IDF install needed)"
task :flash => :setup_espflash do
  chip = build_project_description["target"]
  port_args = ENV["PORT"] ? ["--port", ENV["PORT"]] : []
  flash_files = JSON.parse(File.read(File.join(R2P2_ESP32_ROOT, "build", "flasher_args.json")))["flash_files"]

  FileUtils.cd(File.join(R2P2_ESP32_ROOT, "build")) do
    flash_files.sort_by { |addr, _file| Integer(addr, 16) }.each do |addr, file|
      sh ESPFLASH_BIN, "write-bin", addr, file,
         "--chip", chip, "--baud", "460800", "--non-interactive", *port_args
    end
  end
end

desc "Erase factory partition and flash firmware binary"
task :flash_factory => :setup_espflash do
  sh ESPFLASH_BIN, "erase-region", "0x10000", "0x200000", "--non-interactive"
  sh ESPFLASH_BIN, "write-bin", "0x10000", "build/R2P2-ESP32.bin", "--non-interactive"
end

desc "Erase storage partition and flash storage binary"
task :flash_storage => :setup_espflash do
  sh ESPFLASH_BIN, "erase-region", "0x210000", "0x100000", "--non-interactive"
  sh ESPFLASH_BIN, "write-bin", "0x210000", "build/storage.bin", "--non-interactive"
end

desc "Monitor ESP32 serial output via espflash (no Python/ESP-IDF install needed)"
task :monitor => :setup_espflash do
  desc_json = build_project_description
  port_args = ENV["PORT"] ? ["--port", ENV["PORT"]] : []
  sh ESPFLASH_BIN, "monitor",
     "--chip", desc_json["target"],
     "--monitor-baud", desc_json["monitor_baud"].to_s,
     "--elf", File.join("build", desc_json["app_elf"]),
     *port_args
end
