# frozen_string_literal: true

require_relative 'tools/helpers'
require_relative 'tools/setup'
require_relative 'tools/build'
require_relative 'tools/clean'
require_relative 'tools/job_status'
require_relative 'tools/job_log'
require_relative 'tools/serial_list_ports'
require_relative 'tools/serial_connect'
require_relative 'tools/serial_disconnect'
require_relative 'tools/device_exec'
require_relative 'tools/device_log'
require_relative 'tools/device_reset'
require_relative 'tools/device_upload'
require_relative 'tools/device_download'
require_relative 'tools/flash'
require_relative 'tools/qemu_start'
require_relative 'tools/qemu_stop'
require_relative 'tools/qemu_status'
require_relative 'tools/mrbgem_list'
require_relative 'tools/mrbgem_enable'
require_relative 'tools/mrbgem_disable'
require_relative 'tools/mrbgem_scaffold'

module R2p2Mcp
  module Tools
    ALL = [
      Setup, Build, Clean, JobStatus, JobLog,
      SerialListPorts, SerialConnect, SerialDisconnect,
      DeviceExec, DeviceLog, DeviceReset, DeviceUpload, DeviceDownload, Flash,
      QemuStart, QemuStop, QemuStatus,
      MrbgemList, MrbgemEnable, MrbgemDisable, MrbgemScaffold
    ].freeze
  end
end
