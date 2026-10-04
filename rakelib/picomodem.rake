# File transfer to/from the device over PicoModem (RBTP), using the host client that ships with
# picoruby-picomodem (tools/picomodem.rb). It runs on the host picoruby built by `rake setup`
# (mrbgems/picoruby-picomodem/README.md). As with `rake flash`, ENV['PORT'] selects the serial
# port (default of the client: /dev/ttyACM0), and the shell must be at its prompt.
PICOMODEM_TOOL = File.join(MRUBY_ROOT, "mrbgems/picoruby-picomodem/tools/picomodem.rb")

# The host picoruby: PICORUBY, the one `rake setup` built, or one on PATH.
def find_host_picoruby
  built = File.join(MRUBY_ROOT, "build/host/bin/picoruby")
  [ENV["PICORUBY"], (built if File.executable?(built)), on_path("picoruby")].compact.first
end

def run_picomodem(*args)
  picoruby = find_host_picoruby or
    abort "Host picoruby not found. Run `rake setup_<target>` first (or set PICORUBY)."
  port_args = ENV["PORT"] ? ["-d", ENV["PORT"]] : []
  # The client prints the reason itself; exit quietly instead of letting `sh` add a rake backtrace.
  exit 1 unless system(picoruby, PICOMODEM_TOOL, *port_args, *args)
end

namespace :picomodem do
  desc "Upload a file to the device: rake \"picomodem:put[LOCAL,REMOTE]\" (REMOTE defaults to LOCAL's basename)"
  task :put, [:local, :remote] do |_task, args|
    abort "usage: rake \"picomodem:put[LOCAL,REMOTE]\"" unless args[:local]
    run_picomodem "put", args[:local], *[args[:remote]].compact
  end

  desc "Download a file from the device: rake \"picomodem:get[REMOTE,LOCAL]\" (LOCAL defaults to REMOTE's basename)"
  task :get, [:remote, :local] do |_task, args|
    abort "usage: rake \"picomodem:get[REMOTE,LOCAL]\"" unless args[:remote]
    run_picomodem "get", args[:remote], *[args[:local]].compact
  end
end
