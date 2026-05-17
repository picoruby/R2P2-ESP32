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

  case ENV['CONFIG_IDF_TARGET']
  when 'esp32c3'
    conf.cc.flags << '-march=rv32imc_zicsr_zifencei'
  when 'esp32c5', 'esp32c6'
    conf.cc.flags << '-march=rv32imac_zicsr_zifencei'
  when 'esp32p4'
    conf.cc.flags << '-march=rv32imafc_zicsr_zifencei'
    conf.cc.flags << '-mabi=ilp32f'
  end

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
  conf.cc.defines << "USE_WIFI" if ENV['USE_WIFI']

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
  conf.gem core: "picoruby-shell"
  conf.gem core: "picoruby-picoline"
  conf.gem core: "picoruby-vim"

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
  conf.gem core: 'picoruby-rmt'
  conf.gem core: 'picoruby-mbedtls'
  conf.gem core: 'picoruby-socket'
  conf.gem core: 'picoruby-network'
  conf.gem core: 'picoruby-net-mqtt'
  conf.gem core: 'picoruby-net-ntp'
  conf.gem core: 'picoruby-adafruit_sk6812'
end
