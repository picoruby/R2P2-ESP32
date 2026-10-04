# frozen_string_literal: true

require 'strscan'

module R2p2Mcp
  # Renders the raw console stream into plain text lines. The shell redraws its
  # prompt on every keystroke with escape sequences (`\e[1G$> ec\e[0K...`), so
  # simply stripping the sequences is not enough: a minimal line editor model
  # (cursor column, erase-to-end-of-line) is applied instead.
  module Terminal
    ESCAPE = /\e\[([?0-9;]*)([A-Za-z])/

    # Returns [completed_lines, partial_last_line].
    def self.render(bytes)
      Renderer.new(bytes).render
    end

    # One pass over a byte string, keeping the cursor column of the current line.
    class Renderer
      def initialize(bytes)
        @scanner = StringScanner.new(bytes.dup.force_encoding('UTF-8').scrub)
        @lines = []
        @line = []
        @col = 0
      end

      def render
        step until @scanner.eos?
        [@lines, @line.join]
      end

      private

      def step
        if @scanner.scan(ESCAPE)
          escape(@scanner[1], @scanner[2])
        elsif !@scanner.scan(/\e[^\[]?/) # other escapes are ignored
          character(@scanner.getch)
        end
      end

      def escape(arg, final)
        count = arg.empty? ? 1 : arg.to_i
        case final
        when 'G' then @col = [count - 1, 0].max
        when 'C' then @col += count
        when 'D' then @col = [@col - count, 0].max
        when 'K' then erase_line(arg)
        end
      end

      def erase_line(arg)
        if arg == '2'
          @line = []
        elsif arg.empty? || arg == '0'
          @line = @line[0, @col] || []
        end
      end

      def character(char)
        case char
        when "\n" then newline
        when "\r" then @col = 0
        when "\b" then @col = [@col - 1, 0].max
        else put(char)
        end
      end

      def newline
        @lines << @line.join
        @line = []
        @col = 0
      end

      def put(char)
        return if char.ord < 0x20 && char != "\t"

        @line << ' ' while @line.size < @col
        @line[@col] = char
        @col += 1
      end
    end
  end
end
