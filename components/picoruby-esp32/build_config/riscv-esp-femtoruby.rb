MRuby::CrossBuild.new("esp32-femtoruby") do |conf|
  conf.toolchain("gcc")

  conf.cc.command = "riscv32-esp-elf-gcc"
  conf.linker.command = "riscv32-esp-elf-ld"
  conf.archiver.command = "riscv32-esp-elf-ar"

  conf.cc.host_command = "gcc"
  conf.cc.flags << "-Wall"
  conf.cc.flags << "-Wno-format"
  conf.cc.flags << "-Wno-unused-function"
  conf.cc.flags << "-Wno-maybe-uninitialized"
  conf.cc.flags << "-mabi=ilp32f" if %w[esp32p4].include? ENV['CONFIG_IDF_TARGET']

  conf.cc.defines << "MRBC_TICK_UNIT=10"
  conf.cc.defines << "MRBC_TIMESLICE_TICK_COUNT=1"
  conf.cc.defines << "MRBC_USE_FLOAT=2"
  conf.cc.defines << "MRBC_CONVERT_CRLF=1"
  conf.cc.defines << "USE_FAT_FLASH_DISK"
  conf.cc.defines << "ESP32_PLATFORM"
  conf.cc.defines << "PICORB_INT64"
  conf.cc.defines << "NDEBUG"
  conf.cc.defines << "CONFIG_ESP_WIFI_ENABLED" unless ENV['CONFIG_ESP_WIFI_ENABLED'].to_s.empty?

  conf.femtoruby(alloc_libc: false)
  conf.gembox 'minimum'
  conf.gembox 'core'
  conf.gembox 'shell'

  # stdlib
  conf.gem core: 'picoruby-rng'
  conf.gem core: 'picoruby-base64'
  conf.gem core: 'picoruby-yaml'

  # peripherals
  conf.gem core: 'picoruby-gpio'
  conf.gem core: 'picoruby-i2c'
  conf.gem core: 'picoruby-spi'
  conf.gem core: 'picoruby-adc'
  conf.gem core: 'picoruby-uart'
  conf.gem core: 'picoruby-pwm'

  # others
  conf.gem core: 'picoruby-esp32'
  conf.gem core: 'picoruby-rmt'
  conf.gem core: 'picoruby-mbedtls'
  conf.gem core: 'picoruby-socket'
  conf.gem core: 'picoruby-network'
  conf.gem core: 'picoruby-net-mqtt'
  conf.gem core: 'picoruby-adafruit_sk6812'
  conf.gem core: 'picoruby-net-ntp'
end
