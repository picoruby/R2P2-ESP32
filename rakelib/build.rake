desc "Build the ESP32 project"
task :build do
  sh "idf.py build"
end

PICORB_VMS.each do |name, vm|
  namespace name do
    desc "Build the ESP32 project with #{name} VM"
    task :build do
      sh "idf.py build -DPICORB_VM=#{vm}"
    end
  end
end
