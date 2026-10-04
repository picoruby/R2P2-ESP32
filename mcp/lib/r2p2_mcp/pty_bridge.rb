# frozen_string_literal: true

require 'pty'
require 'io/console'

module R2p2Mcp
  # Exposes a connected Port as a pty, so that tools expecting a device path (rake picomodem:put / get)
  # can talk to the device without the server giving up its connection. Bytes are relayed both ways
  # until the bridge is closed.
  class PtyBridge
    attr_reader :path

    def initialize(port)
      @port = port
      @master, @slave = PTY.open
      @slave.raw! # no echo or translation, or the device's bytes would be echoed back to it
      @path = @slave.path # @slave stays open here so the master never sees a hang-up between clients
      @port.tee = ->(data) { to_client(data) }
      @relay = Thread.new { relay }
    end

    def close
      @port.tee = nil
      @relay.kill
      @master.close
      @slave.close
    end

    private

    def relay
      loop { @port.write(@master.readpartial(4096)) }
    rescue IOError, SystemCallError
      nil
    end

    def to_client(data)
      @master.write(data)
    rescue IOError, SystemCallError
      nil
    end
  end
end
