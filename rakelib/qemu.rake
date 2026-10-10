QEMU_BUILD_DIR = "build-qemu"
QEMU_EXTRA_ARGS = "-m 8M"

desc "Setup a separate build directory (#{QEMU_BUILD_DIR}) to run R2P2-ESP32 on QEMU (ESP32-S3, UART console)"
task :setup_qemu do
  base_defaults = ENV['SDKCONFIG_DEFAULTS'] || "sdkconfig.defaults"
  qemu_defaults = "#{base_defaults};sdkconfigs/qemu"
  sh "idf.py -B #{QEMU_BUILD_DIR} -D SDKCONFIG_DEFAULTS=\"#{qemu_defaults}\" -D SDKCONFIG=#{QEMU_BUILD_DIR}/sdkconfig set-target esp32s3"
end

desc "Generate a QEMU eFuse image with ADC calibration eFuse set, avoiding a hardware self-calibration hang under QEMU"
task :qemu_efuse do
  efuse_path = File.join(QEMU_BUILD_DIR, "qemu_efuse.bin")
  unless File.exist?(efuse_path)
    sh "idf.py -B #{QEMU_BUILD_DIR} qemu efuse-burn --do-not-confirm BLK_VERSION_MAJOR 1"
  end
end

desc "Run R2P2-ESP32 on QEMU (ESP32-S3) with whichever VM is currently configured (see also femtoruby:qemu / picoruby:qemu). Run `rake setup_qemu` first"
task :qemu => %w[qemu_efuse] do
  sh "idf.py -B #{QEMU_BUILD_DIR} qemu --qemu-extra-args='#{QEMU_EXTRA_ARGS}'"
end

PICORB_VMS.each do |name, vm|
  namespace name do
    desc "Run R2P2-ESP32 on QEMU (ESP32-S3) with #{name} VM. Run `rake setup_qemu` first"
    task :qemu => %w[qemu_efuse] do
      sh "idf.py -B #{QEMU_BUILD_DIR} -D PICORB_VM=#{vm} qemu --qemu-extra-args='#{QEMU_EXTRA_ARGS}'"
    end
  end
end

# Builds build-qemu, regenerates its flash image (so every run starts from a fresh /home, as
# `idf.py qemu` does) and runs QEMU with the UART on a TCP port. `idf.py qemu` cannot do this: it
# fixes the UART to `-serial mon:stdio`, whose Ctrl-A escape breaks binary transfers. Used by the
# MCP server (mcp/); connect with any TCP client, e.g. `nc 127.0.0.1 5555`. Ctrl-C stops QEMU.
#
# QEMU_SERIAL_PORT (default 5555) and QEMU_SERIAL_HOST (default 127.0.0.1; 0.0.0.0 in Docker) pick
# where it listens. The line "[qemu_serve] ready ..." is printed just before QEMU starts.
def qemu_serve(vm = nil)
  Rake::Task[:setup_qemu].invoke unless File.exist?(File.join(QEMU_BUILD_DIR, "sdkconfig"))
  Rake::Task[:qemu_efuse].invoke
  sh "idf.py -B #{QEMU_BUILD_DIR} #{"-D PICORB_VM=#{vm}" if vm} build"
  preinstall_system_files(QEMU_BUILD_DIR)

  flash_size = File.read(File.join(QEMU_BUILD_DIR, "sdkconfig"))[/^CONFIG_ESPTOOLPY_FLASHSIZE="(\w+)"/, 1]
  FileUtils.cd(QEMU_BUILD_DIR) do
    sh "python3 -m esptool --chip=esp32s3 merge_bin --output=qemu_flash.bin --fill-flash-size=#{flash_size} @flash_args"
  end

  host = ENV.fetch("QEMU_SERIAL_HOST", "127.0.0.1")
  port = ENV.fetch("QEMU_SERIAL_PORT", "5555")
  qemu_args = [
    "-M", "esp32s3", "-m", "8M",
    "-drive", "file=#{QEMU_BUILD_DIR}/qemu_flash.bin,if=mtd,format=raw",
    "-drive", "file=#{QEMU_BUILD_DIR}/qemu_efuse.bin,if=none,format=raw,id=efuse",
    "-global", "driver=nvram.esp32s3.efuse,property=drive,value=efuse",
    "-global", "driver=timer.esp32s3.timg,property=wdt_disable,value=true",
    "-global", "driver=ssi_psram,property=is_octal,value=true",
    "-nic", "user,model=open_eth", "-nographic",
    "-serial", "tcp:#{host}:#{port},server,nowait",
  ]
  puts "[qemu_serve] ready: UART on tcp://#{host}:#{port}"
  $stdout.flush
  exec "qemu-system-xtensa", *qemu_args
end

desc "Run QEMU (ESP32-S3) with the UART on a TCP port (QEMU_SERIAL_PORT, default 5555), keeping the configured VM"
task(:qemu_serve) { qemu_serve }

PICORB_VMS.each do |name, vm|
  namespace name do
    desc "Run QEMU (ESP32-S3) with the UART on a TCP port, with #{name} VM"
    task(:qemu_serve) { qemu_serve(vm) }
  end
end
