# frozen_string_literal: true

require 'socket'

module R2p2Mcp
  # Opening a Port: a serial device (`/dev/ttyACM0`) or a TCP socket (`tcp://host:port`, e.g. QEMU's UART).
  # `extend`ed into Port.
  module PortOpening
    def open(target, baud: Port::DEFAULT_BAUD)
      new(target, open_io(target, baud))
    end

    def open_io(target, baud)
      if target.start_with?('tcp://')
        host, port = target.delete_prefix('tcp://').split(':')
        TCPSocket.new(host, Integer(port))
      else
        require 'serialport'
        SerialPort.new(target, baud, 8, 1, SerialPort::NONE)
      end
    end

    def tcp?(target) = target.start_with?('tcp://')
  end
end
