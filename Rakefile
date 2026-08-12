R2P2_ESP32_ROOT = File.dirname(File.expand_path(__FILE__))
MRUBY_ROOT = File.join(R2P2_ESP32_ROOT, "components/picoruby-esp32/picoruby")
# VM name => PICORB_VM value; shared by rakelib/build.rake and rakelib/qemu.rake.
PICORB_VMS = { femtoruby: :mrubyc, picoruby: :mruby }.freeze
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

# All other tasks live under rakelib/ (auto-loaded by `rake`): setup.rake, build.rake, qemu.rake,
# flash.rake, clean.rake, wifi_config.rake, docker.rake.
