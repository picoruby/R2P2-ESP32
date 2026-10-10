require "fileutils"
require "json"
require "zlib"

# Regenerates <build_dir>/storage.bin (built by `idf.py build` from storage/) with the system
# executables (/bin/*, /etc/init.d/r2p2) preinstalled, so that the first boot after flashing only
# has to verify them (Shell.ensure_system_file) instead of writing them to the flash.
#
# The bytecode is taken from the same generated C sources that are linked into the firmware, so
# each file matches the size and CRC the firmware checks. /etc/machine-id and
# /etc/ruby-description are left out: they are device/build specific and written on the device.
#
# Note: `idf.py build` / `idf.py flash` regenerate storage.bin from storage/ again. The firmware
# still works with that image; it just writes the executables on the first boot as before.
def preinstall_system_files(build_dir = "build")
  build_dir = File.join(R2P2_ESP32_ROOT, build_dir)
  storage_bin = File.join(build_dir, "storage.bin")
  littlefs_py = File.join(build_dir, "littlefs_py_venv", "bin", "littlefs-python")
  unless File.file?(storage_bin) && File.executable?(littlefs_py)
    warn "preinstall_system_files: #{storage_bin} or littlefs-python not found; skipped"
    return
  end

  vm = File.read(File.join(build_dir, "CMakeCache.txt"))[/^PICORB_VM:\w+=(\w+)/, 1]
  build_name = vm == "mruby" ? "esp32-picoruby" : "esp32-femtoruby"
  inc_file = File.join(MRUBY_ROOT, "build", build_name, "mrbgems", "picoruby-shell", "shell_executables.c.inc")
  unless File.file?(inc_file)
    warn "preinstall_system_files: #{inc_file} not found; skipped"
    return
  end

  image_dir = File.join(build_dir, "storage_image")
  FileUtils.rm_rf(image_dir)
  FileUtils.mkdir_p(image_dir)
  FileUtils.cp_r(File.join(R2P2_ESP32_ROOT, "storage", "."), image_dir)
  # Same directories as Shell.setup_system_files creates
  %w[bin home etc etc/init.d etc/network etc/dfu var var/log lib].each do |dir|
    FileUtils.mkdir_p(File.join(image_dir, dir))
  end

  # The .c.inc may contain absolute paths of another build host (e.g. Docker),
  # so the C sources are looked up next to the .c.inc.
  exe_dir = File.join(File.dirname(inc_file), "shell_executables")
  count = 0
  File.read(inc_file).scan(/\{"([^"]+)", executable_(\w+), (\d+)\}/) do |path, name, crc|
    src = File.join(exe_dir, "#{name.tr('_', '-')}.c")
    src = File.join(exe_dir, "#{name}.c") unless File.file?(src)
    body = File.read(src)[/executable_#{name}\[\]\s*=\s*\{(.*?)\};/m, 1] or
      abort "preinstall_system_files: bytecode array not found in #{src}"
    code = body.scan(/0x\h\h/).map(&:hex).pack("C*")
    # Same as mrb_next_executable(): the size is taken from the RITE header
    code = code.byteslice(0, code.byteslice(8, 4).unpack1("N"))
    # Same as the CRC computed in picoruby-shell/mrbgem.rake
    abort "preinstall_system_files: CRC mismatch for #{path}" unless Zlib.crc32(code.chomp) == crc.to_i
    dest = File.join(image_dir, path)
    FileUtils.mkdir_p(File.dirname(dest))
    File.binwrite(dest, code)
    count += 1
  end

  # Same parameters as littlefs_create_partition_image() of the joltwallet/littlefs component
  name_max = JSON.parse(File.read(File.join(build_dir, "config", "sdkconfig.json")))["LITTLEFS_OBJ_NAME_LEN"]
  sh littlefs_py, "create", image_dir, storage_bin,
     "--fs-size=#{File.size(storage_bin)}", "--name-max=#{name_max}", "--block-size=4096"
  puts "preinstall_system_files: #{count} system executables preinstalled into #{storage_bin}"
end

desc "Regenerate build/storage.bin with the system executables preinstalled (done by the build tasks)"
task(:storage_image) { preinstall_system_files }
