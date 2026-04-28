require 'machine'
require "watchdog"
Watchdog.disable
require "shell"
STDIN = IO.new
STDOUT = IO.new

# Setup flash disk
begin
  STDIN.echo = false
  puts "Initializing FLASH disk as the root volume... "
  Shell.setup_root_volume(:flash, label: 'storage')
  Shell.setup_system_files
  puts "Available"
rescue => e
  puts "Not available"
  puts "#{e.message} (#{e.class})"
end

begin
  if Machine.wifi_available?
    ARGV[0] = "--check-auto-connect"
    load "/bin/wifi_connect"
    ARGV.clear
  end

  GC.start

  if File.exist?("/home/app.mrb")
    puts "Loading app.mrb"
    load "/home/app.mrb"
  elsif File.exist?("/home/app.rb")
    puts "Loading app.rb"
    load "/home/app.rb"
  end

  GC.start

  $shell = Shell.new(clean: true)
  puts "Starting shell...\n\n"

  $shell.show_logo
  $shell.start
rescue => e
  puts "#{e.message} (#{e.class})"
end
