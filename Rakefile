R2P2_ESP32_ROOT = File.dirname(File.expand_path(__FILE__))
MRUBY_ROOT = File.join(R2P2_ESP32_ROOT, "components/picoruby-esp32/picoruby")
# VM name => PICORB_VM value; shared by rakelib/build.rake and rakelib/qemu.rake.
PICORB_VMS = { femtoruby: :mrubyc, picoruby: :mruby }.freeze
MRUBY_SUBMODULE = File.join(MRUBY_ROOT, "mrbgems/picoruby-mruby/lib/mruby")
$LOAD_PATH << File.join(MRUBY_ROOT, "lib") << File.join(MRUBY_SUBMODULE, "lib")

# load build systems
require "mruby/core_ext"
require "mruby/build"
require "picoruby/build"

Dir["#{MRUBY_SUBMODULE}/tasks/toolchains/*.rake"].each {|f| load f}

# load configuration file
MRUBY_CONFIG = MRuby::Build.mruby_config_path
load MRUBY_CONFIG

desc "Default task that runs all main tasks"
task :default => :all

desc "Build, flash, and monitor the ESP32 project"
task :all => %w[build flash monitor]

# All other tasks live under rakelib/ (auto-loaded by `rake`): setup.rake, build.rake, qemu.rake,
# flash.rake, clean.rake, wifi_config.rake, docker.rake.
