# Bind-mounts the project; the Docker file-sharing backend must handle symlinks (virtiofs works, Rancher Desktop's reverse-sshfs/9p doesn't).
DOCKER_IDF_TAG = ENV.fetch("ESP_IDF_DOCKER_TAG", "v5.5.4")
DOCKER_DIR     = File.join(R2P2_ESP32_ROOT, "docker")
DOCKER_IMAGE   = "r2p2-esp32-idf:#{DOCKER_IDF_TAG}"
DOCKER_MOUNT   = "/project"

require "shellwords"

DOCKER_BUNDLE_SHIM = 'export PATH=/tmp/bin:$PATH; mkdir -p /tmp/bin; ' \
  'command -v bundle >/dev/null || ' \
  'for b in /usr/bin/bundle[0-9.]*; do [ -x "$b" ] && ln -sf "$b" /tmp/bin/bundle && break; done'

def docker_clean_stale_host_build!
  mrbc = File.join(MRUBY_ROOT, "build/host/bin/mrbc")
  return unless File.exist?(mrbc) && File.binread(mrbc, 4) != "\x7FELF"
  rm_rf File.join(MRUBY_ROOT, "build/host")
  rm_rf File.join(MRUBY_ROOT, "bin")
end

def docker_run(cmd, tty: false)
  sh "docker build -t #{DOCKER_IMAGE} --build-arg ESP_IDF_DOCKER_TAG=#{DOCKER_IDF_TAG} #{DOCKER_DIR} >/dev/null"
  docker_clean_stale_host_build!

  tty_args = tty ? "-it" : ""
  env_file_arg = File.exist?(File.join(R2P2_ESP32_ROOT, ".env")) ? "--env-file #{R2P2_ESP32_ROOT}/.env" : ""
  full_cmd = "#{DOCKER_BUNDLE_SHIM}; #{cmd}"
  sh <<~SHELL
    docker run --rm #{tty_args} \
    -v #{R2P2_ESP32_ROOT}:#{DOCKER_MOUNT} -w #{DOCKER_MOUNT} \
    -u #{Process.uid}:#{Process.gid} -e HOME=/tmp \
    -e IDF_GIT_SAFE_DIR='*' -e BUNDLE_PATH=#{DOCKER_MOUNT}/.bundle-docker \
    -e CCACHE_DIR=#{DOCKER_MOUNT}/.ccache #{env_file_arg} \
    #{DOCKER_IMAGE} bash -lc #{Shellwords.escape(full_cmd)}
  SHELL
end

namespace :docker do
  desc "Ensure git submodules are checked out on the host before running in Docker"
  task :submodules do
    unless File.exist?(File.join(MRUBY_ROOT, "Rakefile"))
      sh "git submodule update --init --recursive"
    end
  end

  desc "Remove cached gems/ccache (.bundle-docker, .ccache) for a clean slate"
  task :reset do
    rm_rf File.join(R2P2_ESP32_ROOT, ".bundle-docker")
    rm_rf File.join(R2P2_ESP32_ROOT, ".ccache")
  end

  desc "Open an interactive shell in the espressif/idf container"
  task :shell => :submodules do
    docker_run "bash", tty: true
  end

  # Mirror each host-side rake task 1:1 inside the container; "a:b" entries become a nested namespace.
  %w[setup build clean deep_clean qemu setup_qemu
     setup_esp32 setup_esp32c3 setup_esp32c6 setup_esp32h2 setup_esp32p4 setup_esp32s3
     picoruby:build femtoruby:build picoruby:qemu femtoruby:qemu].each do |t|
    desc "Run `rake #{t}` inside the espressif/idf Docker container"
    if t.include?(":")
      ns, name = t.split(":", 2)
      namespace ns.to_sym do
        task name.to_sym => "docker:submodules" do
          docker_run "rake #{t}"
        end
      end
    else
      task t.to_sym => :submodules do
        docker_run "rake #{t}"
      end
    end
  end
end

desc "Like `rake all`, but build in Docker (see docker:build), then flash/monitor from the host"
task :docker => %w[docker:build flash monitor]
