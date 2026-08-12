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
