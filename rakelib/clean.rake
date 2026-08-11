desc "Clean build artifacts"
task :clean do
  sh "idf.py clean"
  FileUtils.cd MRUBY_ROOT do
    %w[xtensa-esp-femtoruby riscv-esp-femtoruby xtensa-esp-picoruby riscv-esp-picoruby].each do |mruby_config|
      sh "MRUBY_CONFIG=#{R2P2_ESP32_ROOT}/components/picoruby-esp32/build_config/#{mruby_config}.rb rake clean"
    end
  end
end

desc "Perform deep clean including ESP32 build repos"
task :deep_clean => %w[clean] do
  sh "idf.py fullclean"
  rm_rf File.join(MRUBY_ROOT, "build/repos/esp32")
end
