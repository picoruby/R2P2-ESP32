# frozen_string_literal: true

module R2p2Mcp
  # Builds the MCP server with all tools and serves it over stdio.
  module Server
    INSTRUCTIONS = <<~TEXT
      R2P2-ESP32: PicoRuby firmware for ESP32. Flow for a connected board: setup (target, e.g. esp32s3; add
      sdkconfigs ["usb_console"] for boards whose console is the native USB port) -> build -> flash ->
      device_upload your script -> device_exec "./app.rb". Pass the same sdkconfigs to setup and build.
      setup / build / flash wait for the result (timeout, default 300 s); if one returns "still running", call
      job_wait. build defaults to the picoruby (mruby) VM. The serial port is held by this server until
      serial_disconnect. The device shell has no `>` redirection (`echo ... > file` crashed the mruby/c build):
      create files with device_upload (content: ...). Without hardware, qemu_start gives the same device_* tools.
    TEXT

    def self.run
      server = MCP::Server.new(name: 'r2p2-esp32', version: '0.1.0', tools: Tools::ALL, instructions: INSTRUCTIONS)
      MCP::Server::Transports::StdioTransport.new(server).open
    end
  end
end
