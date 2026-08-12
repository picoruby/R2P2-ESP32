# Read from build/project_description.json rather than hardcoding, so this tracks whatever
# target/VM the build was last configured for.
def build_project_description
  require "json"
  JSON.parse(File.read(File.join(R2P2_ESP32_ROOT, "build", "project_description.json")))
end

# ENV['PORT'] overrides the serial port; otherwise esptool/esp_idf_monitor auto-detect it.
desc "Flash the built firmware to ESP32 via esptool (no ESP-IDF install needed; `pip install esptool`)"
task :flash do
  port = ENV["PORT"] ? "--port #{ENV['PORT']}" : ""
  FileUtils.cd(File.join(R2P2_ESP32_ROOT, "build")) do
    sh "esptool.py --chip #{build_project_description['target']} #{port} " \
       "-b 460800 --before default_reset --after hard_reset write_flash @flash_args"
  end
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

desc "Monitor ESP32 serial output via esp-idf-monitor (no ESP-IDF install needed; `pip install esp-idf-monitor`)"
task :monitor do
  desc_json = build_project_description
  port = ENV["PORT"] ? "--port #{ENV['PORT']}" : ""
  sh "python3 -m esp_idf_monitor #{port} -b #{desc_json['monitor_baud']} build/#{desc_json['app_elf']}"
end
