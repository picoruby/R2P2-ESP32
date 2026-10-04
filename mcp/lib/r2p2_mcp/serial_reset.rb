# frozen_string_literal: true

module R2p2Mcp
  # Resetting a board through the serial port's control lines (mixed into Port; uses its @io).
  #
  # On a USB Serial/JTAG console RTS drives EN (reset) and DTR drives GPIO0 (boot mode): DTR must stay low
  # while leaving reset, or the chip drops into the ROM download mode. Changing DTR alone on a running board
  # can do that too, so nothing else here touches the control lines.
  module SerialReset
    def serial? = !@io.is_a?(TCPSocket)

    # Resets the board into the app the way esptool does, then leaves the lines as for a plainly open port.
    def hard_reset
      raise 'a DTR/RTS reset needs a serial port' unless serial?

      @io.rts = 0
      @io.dtr = 0 # (DTR, RTS) = (0, 0): idle
      @io.rts = 1 # (0, 1): reset
      sleep 0.1
      @io.rts = 0 # (0, 0): out of reset, the app boots
      sleep 0.05
      @io.dtr = 1 # (1, 0)
      @io.rts = 1 # (1, 1)
    end
  end
end
