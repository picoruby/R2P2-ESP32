# frozen_string_literal: true

require 'mcp'

module R2p2Mcp
  # Repository root (mcp/ lives directly under it).
  ROOT = File.expand_path('../..', __dir__)
end

require_relative 'r2p2_mcp/job_manager'
require_relative 'r2p2_mcp/rake_task'
require_relative 'r2p2_mcp/terminal'
require_relative 'r2p2_mcp/port'
require_relative 'r2p2_mcp/command_runner'
require_relative 'r2p2_mcp/pty_bridge'
require_relative 'r2p2_mcp/device_recovery'
require_relative 'r2p2_mcp/device'
require_relative 'r2p2_mcp/qemu'
require_relative 'r2p2_mcp/mrbgem'
require_relative 'r2p2_mcp/build_config'
require_relative 'r2p2_mcp/scaffold'
require_relative 'r2p2_mcp/tools'
require_relative 'r2p2_mcp/server'
