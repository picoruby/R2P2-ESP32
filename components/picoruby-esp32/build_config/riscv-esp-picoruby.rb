MRuby::CrossBuild.new('esp32-picoruby') do |conf|
  conf.toolchain('gcc')

  conf.cc.command = 'riscv32-esp-elf-gcc'
  conf.linker.command = 'riscv32-esp-elf-ld'
  conf.archiver.command = 'riscv32-esp-elf-ar'

  conf.cc.host_command = 'gcc'
  conf.cc.flags << '-Wall'
  conf.cc.flags << '-Wno-format'
  conf.cc.flags << '-Wno-unused-function'
  conf.cc.flags << '-Wno-maybe-uninitialized'
  conf.cc.flags << "-mabi=ilp32f" if %w[esp32p4].include? ENV['CONFIG_IDF_TARGET']

  conf.cc.defines << 'MRB_TICK_UNIT=10'
  conf.cc.defines << 'MRB_TIMESLICE_TICK_COUNT=1'
  conf.cc.defines << 'MRBC_CONVERT_CRLF=1'
  conf.cc.defines << 'MRB_UTF8_STRING'
  conf.cc.defines << 'MRB_INT64'
  conf.cc.defines << 'MRB_NO_BOXING'
  conf.cc.defines << 'MRB_32BIT'
  conf.cc.defines << 'PICORB_ALLOC_ESTALLOC'
  conf.cc.defines << 'PICORB_ALLOC_ALIGN=8'
  conf.cc.defines << 'USE_FAT_FLASH_DISK'
  conf.cc.defines << 'NDEBUG'
  conf.cc.defines << 'ESP32_PLATFORM'

  if ENV['PICORB_DEBUG']
    conf.cc.defines << 'ESTALLOC_DEBUG'
    conf.enable_debug
  end

  conf.picoruby
  conf.gembox 'minimum'
  conf.gembox 'core'
  conf.gem gemdir: '../picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-kernel-ext'
  conf.gem gemdir: '../picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-string-ext'
  conf.gem gemdir: '../picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-array-ext'
  conf.gem gemdir: '../picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-objectspace'
  conf.gem gemdir: '../picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-metaprog'
  conf.gem gemdir: '../picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-error'
  conf.gem gemdir: '../picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-sprintf'
  conf.gem gemdir: '../picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-math'
  conf.gem core: 'picoruby-esp32'
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
  # conf.gem core: 'picoruby-rmt'
  conf.gem core: 'picoruby-mbedtls'
  conf.gem core: 'picoruby-socket'
  # conf.gem core: 'picoruby-adafruit_sk6812'
end
