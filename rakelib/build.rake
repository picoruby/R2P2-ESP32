# frozen_string_literal: true

# Runs on the host with ESP-IDF; the task of the same name without `native:` runs it in Docker
# (rakelib/docker.rake).
namespace :native do
  desc 'Build the ESP32 project'
  task :build do
    sh 'idf.py build'
    preinstall_system_files
  end

  PICORB_VMS.each do |name, vm|
    namespace name do
      desc "Build the ESP32 project with #{name} VM"
      task :build do
        sh "idf.py build -DPICORB_VM=#{vm}"
        preinstall_system_files
      end
    end
  end
end
