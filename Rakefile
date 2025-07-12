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

task :default => :all
task :all => %w[build flash monitor]

task :setup do
  FileUtils.cd MRUBY_ROOT do
    sh "bundle install"
    sh "rake"
  end
end

%w[esp32 esp32c3 esp32c6 esp32s3].each do |name|
  task "setup_#{name}" => %w[deep_clean setup] do
    sh "idf.py set-target #{name}"
  end
end

task :build do
  sh "idf.py build"
end

task :flash do
  sh "idf.py flash"
end

task :flash_factory do
  sh "esptool.py -b 460800 erase_region 0x10000 0x100000"
  sh "esptool.py -b 460800 write_flash 0x10000 build/R2P2-ESP32.bin"
end

task :flash_storage do
  sh "esptool.py -b 460800 erase_region 0x110000 0x100000"
  sh "esptool.py -b 460800 write_flash 0x110000 build/storage.bin"
end

task :monitor do
  sh "idf.py monitor"
end

task :clean do
  sh "idf.py clean"
  FileUtils.cd MRUBY_ROOT do
    %w[xtensa-esp riscv-esp].each do |mruby_config|
      sh "MRUBY_CONFIG=#{mruby_config} rake clean"
    end
  end
end

task :deep_clean => %w[clean] do
  sh "idf.py fullclean"
  rm_rf File.join(MRUBY_ROOT, "build/repos/esp32")
end
