# R2P2-ESP32 MCP server

An [MCP](https://modelcontextprotocol.io/) server for developers of PicoRuby firmware on ESP32. It
lets an AI assistant run the whole loop: build, flash, talk to the device (shell commands, logs, file
transfer), and try things without hardware on QEMU, plus manage mrbgems.

> **Status:** the device tools were verified against QEMU only; they have not been tried on real
> hardware yet. Open points for real boards: opening a USB Serial/JTAG port may reset the board
> (DTR/RTS), and `flash` reconnects after a fixed 2 s wait.

## Requirements

- Ruby (the version the repo already requires for building, e.g. 4.0.x) and Bundler
- Docker (the default build environment; see [Building with Docker](../README.md#building-with-docker))
- Submodules checked out (`git submodule update --init --recursive`)

## Install

```sh
cd mcp
bundle install
```

Use the same Ruby the MCP client will start the server with. If the gems are missing, the server
exits at startup with a hint on stderr (your client shows it as the server's error); run the
`bundle install` it names, then restart the server. The `rubocop` gem (development group) is
not needed to run the server: `bundle config set --local without development` skips it.

## Register with your MCP client

The repository root has a `.mcp.json`, so Claude Code picks the server up automatically when
started in this repository (approve it when prompted). For other clients, run
`mcp/bin/r2p2-esp32-mcp` as a stdio server, for example:

```sh
claude mcp add r2p2-esp32 -- /path/to/R2P2-ESP32/mcp/bin/r2p2-esp32-mcp
```

## Tools

`setup`, `build`, `clean` and `flash` run the rake task as a job and **wait for it** (`timeout`,
default 300 s; `0` returns at once). If it takes longer it keeps running and the call says so: follow
it with `job_wait`. Only one job runs at a time. Everything runs in Docker (`rake docker:*`) unless
`native: true` is passed.

| tool | arguments | what it does |
|------|-----------|--------------|
| `setup` | `target` (required: `esp32`, `esp32c3`, `esp32c6`, `esp32h2`, `esp32p4`, `esp32s3`), `sdkconfigs`, `use_wifi`, `native`, `timeout` | `rake setup_<target>`. Deletes the old `sdkconfig` first, because it caches `SDKCONFIG_DEFAULTS`. |
| `build` | `vm` (`picoruby` (default) / `femtoruby`), `sdkconfigs`, `use_wifi`, `native`, `timeout` | `rake <vm>:build` |
| `clean` | `deep`, `native`, `timeout` | `rake clean`, or `deep_clean` with `deep: true` |
| `job_wait` | `job_id` (default: latest), `timeout` (default 300 s) | wait for a job that was still running, then report it |
| `job_status` | `job_id` (default: latest) | running / succeeded / failed, without waiting. On failure, includes extracted error lines and the last 20 log lines. |
| `job_log` | `job_id`, `lines` (default 100) | tail of the job log |

### Device tools

These talk to the device's `picoruby-shell` through one connection held by the server.

| tool | arguments | what it does |
|------|-----------|--------------|
| `serial_list_ports` | | list `/dev/ttyACM*`, `ttyUSB*`, `cu.usb*` ports |
| `serial_connect` | `port` (required), `baud` | connect to a serial device or `tcp://host:port` (e.g. QEMU's UART) and check for the `$> ` prompt. Replaces a previous connection. |
| `serial_disconnect` | | release the port (do this before `rake monitor` or a web terminal) |
| `device_exec` | `command` (required), `timeout` (default 10 s) | run a shell command, return its output when the prompt returns. On timeout: Ctrl-C, then Ctrl-D if still stuck (e.g. in `irb`). If the shell never echoed the command (device still booting or hung), nothing is sent, since a Ctrl-C during boot breaks the shell's start-up, and it says so. |
| `device_log` | `lines` (default 100), `since_last` | everything the device printed since connecting (last 256 KiB kept). Crash markers (`Guru Meditation`, `Backtrace:`, `assert failed`, ...) are listed first. |
| `device_reset` | `timeout` (default 60 s) | shell `reboot`, returns the boot log up to the next prompt. Boot can take up to a minute on some builds, so it is waited for; if the prompt does not come, a serial device is reset through DTR/RTS (like esptool) |
| `device_upload` | `remote_path`, `local_path` or `content` | write a file to the device over RBTP (PicoModem) with `rake picomodem:put`, CRC32-checked. `content` uploads text without a local file, e.g. a script to run next. Default `remote_path`: basename of `local_path`. |
| `device_download` | `remote_path` (required), `local_path` | read a file from the device over RBTP (`rake picomodem:get`) and save it locally |
| `flash` | `port`, `reconnect` (default true), `timeout` | host-side `rake flash`. Releases the serial port first and reconnects after success. Not available while connected to a `tcp://` port. |

File transfer needs the shell at its prompt (not inside `irb`) and the host `picoruby` built by
`setup` (on macOS, a Docker-only build leaves a Linux binary there; run `rake setup_<target>`
natively once). The server keeps its connection open: it bridges the port to a pty and hands that
to the rake task, so it works for serial devices and QEMU alike. The binary traffic is hidden from
`device_log`; one `[rbtp] put ...` line is logged instead.

Console output is rendered to plain text (the shell redraws its prompt with escape sequences on
every keystroke, which is applied rather than shown).

### QEMU

Run the firmware without hardware (ESP32-S3 on QEMU; no peripherals, no WiFi), for checking logic
and scripts. The UART is exposed on `tcp://127.0.0.1:5555` and connected like a serial port, so all
`device_*` tools work on it.

| tool | arguments | what it does |
|------|-----------|--------------|
| `qemu_start` | `vm`, `native`, `timeout` (default 120 s) | `rake qemu_serve`: builds `build-qemu` (set up automatically; the first time takes minutes), starts QEMU in Docker with a fresh `/home`, connects to its shell. If it is still building after `timeout`, it keeps going in the background. |
| `qemu_status` | `lines` | running / building, and the tail of its rake / build output |
| `qemu_stop` | | stop QEMU (its `/home` is discarded) |

`flash` is not available while connected to QEMU. See [Running on QEMU](../README.md#running-on-qemu-esp32-s3)
for its limitations (no ADC, WiFi, ...).

### mrbgems

Which gems the firmware contains is decided by `components/picoruby-esp32/build_config/*.rb` (one
file per architecture x VM). Your own gems live in `mrbgems/` at the repository root.

| tool | arguments | what it does |
|------|-----------|--------------|
| `mrbgem_list` | `query`, `enabled_only` | gems (custom first, then picoruby's) and where each is enabled; "via X" means a gembox provides it |
| `mrbgem_enable` | `name`, `vm`, `arch` | add the gem to the build configs (all four by default); `picoruby-` prefix optional |
| `mrbgem_disable` | `name`, `vm`, `arch` | remove it; gems provided by a gembox cannot be removed this way |
| `mrbgem_scaffold` | `name`, `summary`, `author`, `enable` | create `mrbgems/picoruby-<name>/` (pure Ruby: `mrbgem.rake`, `mrblib`, `sig`, `test`, `README.md`), usable as `require "<name>"` on both VMs |

After changing gems, run `build` (or `qemu_start` to try it without hardware). Example: `mrbgem_scaffold`
with `enable: true`, edit `mrbgems/picoruby-<name>/mrblib/<name>.rb`, `qemu_start`, then `device_upload`
a script that requires it and `device_exec` it. Gems with C code are not scaffolded; copy an existing
gem (e.g. `picoruby-base64`) as a starting point.

`sdkconfigs` are names of the fragment files under `sdkconfigs/` (e.g. `usb_console`,
`spiram`), the same ones you would put in `SDKCONFIG_DEFAULTS`. `use_wifi` sets `USE_WIFI=1`.

Pass the same `sdkconfigs` / `use_wifi` to `build` as to `setup`. Changing them requires running
`setup` again.

### Typical flow

1. `setup` with `target: "esp32s3"`, `sdkconfigs: ["usb_console", "spiram"]`
2. `build` (the picoruby VM by default; same `sdkconfigs`)
3. `flash`; the server reconnects to the port afterwards
4. `device_upload` your script, then `device_exec` (`./app.rb`) and `device_log` to see what happened

Steps 1 to 3 return when the job is done (see `job_wait` for one that outlasts `timeout`).

## Notes

- Docker only forwards `SDKCONFIG_DEFAULTS` and `USE_WIFI` from the environment (this is how the
  server passes `sdkconfigs` / `use_wifi`); anything else still goes through `.env`. See
  [Building with Docker](../README.md#building-with-docker).
- Job logs are kept in a temporary directory and removed when the server exits.

## Development

```sh
cd mcp
bundle exec rubocop   # style check; config in .rubocop.yml (defaults + NewCops)
```
