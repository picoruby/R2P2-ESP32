R2P2_ESP32_ROOT = File.dirname(File.expand_path(__FILE__))
MRUBY_ROOT = File.join(R2P2_ESP32_ROOT, "components/picoruby-esp32/picoruby")
$LOAD_PATH << File.join(MRUBY_ROOT, "lib")

# load build systems
require "mruby/core_ext"
require "mruby/build"
require "picoruby/build"

# load configuration file
MRUBY_CONFIG = MRuby::Build.mruby_config_path
load MRUBY_CONFIG

desc "Default task that runs all main tasks"
task :default => :all

desc "Build, flash, and monitor the ESP32 project"
task :all => %w[build flash monitor]

desc "Install dependencies and build mruby"
task :setup do
  FileUtils.cd MRUBY_ROOT do
    sh "bundle install"
    sh "rake"
  end
end

%w[esp32 esp32s2 esp32s3 esp32c3 esp32c6 esp32h2 esp32p4].each do |name|
  desc "Setup environment for #{name} target"
  task "setup_#{name}" => %w[deep_clean setup] do
    sh "idf.py set-target #{name}"
  end
end

desc "Build the ESP32 project"
task :build do
  sh "idf.py build"
end

{ femtoruby: :mrubyc, picoruby: :mruby }.each do |name, vm|
  namespace name do
    desc "Build the ESP32 project with #{name} VM"
    task :build do
      sh "idf.py build -DPICORB_VM=#{vm}"
    end
  end
end

desc "Flash the built firmware to ESP32"
task :flash do
  sh "idf.py flash"
end

desc "Erase factory partition and flash firmware binary"
task :flash_factory do
  sh "esptool.py -b 460800 erase_region 0x10000 0x200000"
  sh "esptool.py -b 460800 write_flash 0x10000 build/R2P2-ESP32.bin"
end

desc "Erase storage partition and flash storage binary"
task :flash_storage do
  sh "esptool.py -b 460800 erase_region 0x210000 0x100000"
  sh "esptool.py -b 460800 write_flash 0x210000 build/storage.bin"
end

desc "Monitor ESP32 serial output"
task :monitor do
  sh "idf.py monitor"
end

desc "Clean build artifacts"
task :clean do
  sh "idf.py clean"
  FileUtils.cd MRUBY_ROOT do
    %w[xtensa-esp-femtoruby riscv-esp-femtoruby xtensa-esp-picoruby riscv-esp-picoruby].each do |mruby_config|
      sh "MRUBY_CONFIG=#{R2P2_ESP32_ROOT}/components/picoruby-esp32/build_config/#{mruby_config}.rb rake clean"
    end
  end
end

desc "Perform deep clean including ESP32 build repos"
task :deep_clean => %w[clean] do
  sh "idf.py fullclean"
  rm_rf File.join(MRUBY_ROOT, "build/repos/esp32")
end

desc "Generate storage/etc/network/wifi.yml for WiFi auto-connect"
task :gen_wifi_config do
  require 'openssl'
  require 'base64'
  require 'yaml'

  ssid      = ENV['SSID']      or abort "SSID is required. Usage: rake gen_wifi_config SSID=... PASSWORD=... UNIQUE_ID=..."
  password  = ENV['PASSWORD']  or abort "PASSWORD is required."
  unique_id = ENV['UNIQUE_ID'] or abort "UNIQUE_ID is required. Get it from Machine.unique_id on the device."

  # AES-256-CBC encryption (same as wifi_connect.rb decrypt logic)
  key_len = 32
  iv_len  = 16
  len = unique_id.length
  key = (unique_id * ((key_len / len + 1) * len))[0, key_len]
  iv  = (unique_id * ((iv_len  / len + 1) * len))[0, iv_len]

  cipher = OpenSSL::Cipher.new('AES-256-CBC')
  cipher.encrypt
  cipher.key = key
  cipher.iv  = iv
  ciphertext = cipher.update(password) + cipher.final

  encoded_password = Base64.strict_encode64(ciphertext)

  doc = {
    'wifi' => {
      'ssid' => ssid,
      'encoded_password' =>  encoded_password,
      'auto_connect' => (ENV.fetch('AUTO_CONNECT', 'true') == 'true'),
      'retry_if_failed' => (ENV.fetch('RETRY_IF_FAILED', 'true') == 'true'),
      'watchdog' => (ENV.fetch('WATCHDOG', 'false') == 'true')
    }
  }
  doc['country_code'] = ENV['COUNTRY_CODE'] if ENV['COUNTRY_CODE']

  output_path = File.join(R2P2_ESP32_ROOT, "storage/etc/network/wifi.yml")
  FileUtils.mkdir_p(File.dirname(output_path))
  File.write(output_path, YAML.dump(doc).sub(/\A---\s*\n/, ''))
  puts "Generated: #{output_path}"
end
