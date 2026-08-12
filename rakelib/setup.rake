# Locate a host (non-cross) toolchain command. ESP-IDF's activation script
# prepends its cross toolchains to PATH, so resolve the command against PATH
# entries outside the ESP-IDF installation. HOST_CC / HOST_AR override the
# detection.
def find_host_tool(*names)
  override = ENV["HOST_#{names.first.upcase}"]
  return override if override

  host_path = ENV['PATH'].split(File::PATH_SEPARATOR)
                         .reject { |dir| dir.match?(/\.espressif|esp-idf/) }
  names.each do |name|
    host_path.each do |dir|
      candidate = File.join(dir, name)
      return candidate if File.file?(candidate) && File.executable?(candidate)
    end
  end
  abort "Host toolchain `#{names.join('`/`')}` not found in PATH. Set HOST_#{names.first.upcase} to specify it."
end

desc "Install dependencies and build mruby"
task :setup do
  host_env = {
    'CC' => find_host_tool('cc', 'gcc', 'clang'),
    'AR' => find_host_tool('ar')
  }
  FileUtils.cd MRUBY_ROOT do
    sh "bundle install"
    sh host_env, "rake"
  end
end

%w[esp32 esp32c3 esp32c6 esp32h2 esp32p4 esp32s3].each do |name|
  desc "Setup environment for #{name} target"
  task "setup_#{name}" => %w[deep_clean setup] do
    sh "idf.py set-target #{name}"
  end
end
