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

%w[esp32 esp32c3 esp32c6 esp32s3].each do |name|
  desc "Setup environment for #{name} target"
  task "setup_#{name}" => %w[deep_clean setup] do
    sh "idf.py set-target #{name}"
  end
end

desc "Build the ESP32 project"
task :build do
  sh "idf.py build"
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
    %w[xtensa-esp riscv-esp].each do |mruby_config|
      sh "MRUBY_CONFIG=#{mruby_config} rake clean"
    end
  end
end

desc "Perform deep clean including ESP32 build repos"
task :deep_clean => %w[clean] do
  sh "idf.py fullclean"
  rm_rf File.join(MRUBY_ROOT, "build/repos/esp32")
end
