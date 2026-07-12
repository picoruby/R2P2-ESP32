# dap_debug_sample.rb
#
# Shows how to start picoruby-debug's DAP server on ESP32 once WiFi is up,
# so an editor (VS Code, Zed, ...) can attach to it as a remote debugger.
#
# Prerequisites:
#   - Firmware built with USE_WIFI=1 and the PicoRuby (mruby) VM, i.e.
#       USE_WIFI=1 rake picoruby:build
#     See README.md, "Enabling WiFi (USE_WIFI)" and
#     "Remote debugging over WiFi (DAP)".
#   - The picoruby-debug gem must be in the build config (already added to
#     components/picoruby-esp32/build_config/xtensa-esp-picoruby.rb /
#     riscv-esp-picoruby.rb).
#
# Run this from the picoruby-shell prompt:
#   $> ./dap_debug_sample.rb
#
# This script blocks at `binding.debugger` until a DAP client (an editor)
# connects and completes its handshake, then behaves like a normal
# breakpoint from then on.

require 'debug'
require 'network'

DAP_PORT = 4711

# --- 1. Make sure WiFi is connected before opening the DAP port ---
#
# If /etc/network/wifi.yml has `auto_connect: true` (see
# `rake gen_wifi_config`), main_task.rb has already connected by the time
# the shell prompt appears, so this block is skipped. Otherwise, fall back
# to a manual connect using WIFI_SSID / WIFI_PASSWORD from the environment.
unless Network::WiFi.link_connected?
  ssid = ENV['WIFI_SSID']
  password = ENV['WIFI_PASSWORD']
  unless ssid
    puts "WiFi is not connected and WIFI_SSID is not set. Aborting."
    puts "Set up storage/etc/network/wifi.yml (rake gen_wifi_config), or"
    puts "export WIFI_SSID / WIFI_PASSWORD before running this script."
    return
  end

  puts "WiFi not connected yet, connecting to #{ssid}..."
  Network::WiFi.init("JP") unless Network::WiFi.initialized?
  Network::WiFi.enable_sta_mode

  auth = password && !password.empty? ? Network::WiFi::Auth::WPA2_MIXED_PSK : Network::WiFi::Auth::OPEN
  begin
    connected = Network::WiFi.connect_timeout(ssid, password, auth, 10) # seconds
    unless connected
      puts "Failed to connect to WiFi. Aborting."
      return
    end
  rescue Network::ConnectTimeout
    puts "WiFi connection timed out. Aborting."
    return
  end

  until Network::WiFi.link_connected?
    sleep_ms 100
  end
end

puts "WiFi connected (#{Network::WiFi.tcpip_link_status_name})"

# --- 2. Open the DAP port *before* the first binding.debugger call ---
#
# Debugger.listen_dap only takes effect for the *next* binding.debugger
# call (see picoruby-debug's mrblib/debugger.rb: the DAP session is
# created inside Debugger#initialize, which the first binding.debugger
# call triggers). Calling it after the breakpoint has already fired is
# too late.
Debugger.listen_dap(DAP_PORT)
puts "DAP server will listen on port #{DAP_PORT} once binding.debugger runs."
puts "Attach your editor's DAP client to <this device's IP>:#{DAP_PORT}."
puts "(check the device's IP with: ESP32::WiFi.tcpip_link_status_name, or"
puts "your router's DHCP lease list)"

# --- 3. A tiny program to debug, with a breakpoint ---
def add(a, b)
  a + b
end

binding.debugger # blocks here until a DAP client completes the handshake
puts add(1, 2)
