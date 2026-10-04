# frozen_string_literal: true

module R2p2Mcp
  # Builds the MCP server with all tools and serves it over stdio.
  module Server
    def self.run
      server = MCP::Server.new(name: 'r2p2-esp32', version: '0.1.0', tools: Tools::ALL)
      MCP::Server::Transports::StdioTransport.new(server).open
    end
  end
end
