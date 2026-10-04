# R2P2-ESP32 MCP server — design notes

Status: M1 (build tools), M2 (serial, shell, log, flash), M3 (RBTP file transfer) and M4 (QEMU) and M5 (mrbgem helpers) implemented; M2 to M5 verified on QEMU only.

An MCP server for developers of PicoRuby firmware on ESP32. It lets an AI assistant run the
whole loop: build → flash → talk to the device → read logs → fix, plus a no-hardware loop on QEMU.

## Goals / non-goals

- Goals: automate `rake` build/flash tasks; drive the `picoruby-shell` on a real device or on QEMU
  (run commands, transfer files, read logs).
- Non-goals: documentation lookup (see <https://picoruby.org/R2P2-ESP32-docs/>), safety
  confirmations (out of scope for now), peripheral emulation on QEMU.

## Stack

- Ruby (CRuby 4.0.x, same as the repo's build requirement), under `mcp/`.
- [`mcp` gem](https://github.com/modelcontextprotocol/ruby-sdk) (stdio transport) and `serialport` gem.
- Started via `.mcp.json` at the repo root.

## Concepts

### Port

Everything on the device side goes through one abstraction, **Port**: a duplex byte stream
to a `picoruby-shell`. There are two kinds:

| kind   | transport                                   |
|--------|---------------------------------------------|
| serial | `/dev/ttyACM0` etc. via `serialport`        |
| qemu   | `tcp://127.0.0.1:5555` (see [QEMU](#qemu))  |

The server holds one connected Port at a time and buffers everything it receives in a ring buffer
(this is what `device_log` reads). `device_*` tools operate on the connected Port. The server
releases the serial port when asked (`serial_disconnect`) and automatically before `flash`.

### Jobs

Builds take minutes, so `build`/`setup` run as background jobs: they return a `job_id`, and
`job_status` / `job_log` poll them. Only one build job runs at a time.

## Tools

### Build / flash

| tool | what it does |
|------|--------------|
| `setup`  | `rake docker:setup_<target>`; args: `target`, `sdkconfigs` (e.g. `usb_console`, `spiram`), `use_wifi` |
| `build`  | `rake docker:picoruby:build` / `docker:femtoruby:build`; args: `vm`; returns a job |
| `clean`  | `rake docker:clean` (+ `reset` option) |
| `flash`  | host-side `rake flash` (the container cannot see the serial port); disconnects the Port first |
| `job_status`, `job_log` | poll a job; errors extracted from the log |
| (all)    | `native: true` runs the plain `rake` task instead of `docker:*` |

Docker is the default. `use_wifi` is only read at CMake configure time, so changing it
triggers `reconfigure` (see README).

### Device

| tool | what it does |
|------|--------------|
| `serial_list_ports`, `serial_connect`, `serial_disconnect` | manage the Port |
| `device_exec`  | type a shell command, return its output (up to the next `$> ` prompt) |
| `device_eval`  | (not implemented) run Ruby code through `irb` |
| `device_run`   | (not implemented; `device_exec ./app.rb` with a timeout covers it) |
| `device_ls`    | (not implemented; use `device_exec ls`) |
| `device_upload`, `device_download` | RBTP file transfer (see below; via `rake picomodem:*`); upload takes a local file or inline `content` |
| `device_reset` | shell `reboot`, capture the boot log (no DTR/RTS toggling) |
| `device_log`   | tail the ring buffer; detect panic / backtrace |

### QEMU

| tool | what it does |
|------|--------------|
| `qemu_start` | `rake qemu_serve` in Docker (or native), wait for the shell, connect the Port to it |
| `qemu_status` | running / building, tail of the rake output |
| `qemu_stop`  | stop the container (`docker stop`) |

Meant for checks that need no peripherals (logic, scripts under `/home`, boot checks).

### mrbgem helper

| tool | what it does |
|------|--------------|
| `mrbgem_list` | gems in `picoruby/mrbgems/picoruby-*` and the project's `mrbgems/`, with where each is enabled (parsed from `build_config/*.rb` and the gemboxes they include; gembox conditions are ignored) |
| `mrbgem_enable` / `mrbgem_disable` | add / remove a `conf.gem` line in the selected build configs. Core gems: `conf.gem core: 'x'`; custom: `conf.gem gemdir: File.expand_path('../../../mrbgems/x', __dir__)`. Gems provided by a gembox are reported, not edited |
| `mrbgem_scaffold` | skeleton of a pure-Ruby gem in `mrbgems/picoruby-<name>/` (optionally enabled). C gems are out of scope: the layout differs per VM (`src/mruby`, `src/mrubyc`) |

Build system finding: the custom command that produces `libmruby.a` in
`components/picoruby-esp32/CMakeLists.txt` had no `DEPENDS`, so it only ran while the file did not
exist, and changes to `build_config/*.rb` or to a gem were silently not built. It now depends on the
selected build config and on everything under `mrbgems/` (not on gems inside the picoruby submodule).
Checked: scaffold + enable + `qemu_start` rebuilt (66 s) and `require 'mcp_hello'` worked on QEMU.

## Shell interaction

The shell does line editing, so every keystroke is echoed with ANSI sequences
(`\e[1G$> echo\e[0K...`). `device_exec`:

1. strip ANSI sequences from the received stream,
2. write the command + `\r`,
3. read until the prompt `$> ` reappears (with timeout), drop the echoed command line.

## File transfer (RBTP / PicoModem)

Reference: `components/picoruby-esp32/picoruby/mrbgems/picoruby-picomodem` (README, `tools/picomodem.rb`).

- We reuse the upstream host client instead of reimplementing the protocol. `rakelib/picomodem.rake`
  adds `rake picomodem:put[LOCAL,REMOTE]` / `picomodem:get[REMOTE,LOCAL]`, which run
  `tools/picomodem.rb` on the host `picoruby` built by `rake setup` (`PORT` selects the device, like
  `rake flash`). The MCP tools call these tasks.
- The client opens a device path (`stty -F`, `File.open`), but the server wants to keep its own
  connection (buffered log, no DTR/RTS toggling on reopen, QEMU has no device path at all). So
  `PtyBridge` exposes the connected Port as a pty (raw mode, so nothing is echoed back), relays bytes
  both ways, and its path is passed as `PORT`. One code path for serial and QEMU.
- Frame: `STX | len(2, BE) | cmd | payload | CRC16(2, BE)`; only `FILE_READ`/`FILE_WRITE`/`CHUNK`/`ABORT`
  exist, so `ls`/`rm` go through the shell. Both directions are checked with CRC32.
- While a transfer runs the Port buffer keeps receiving the binary traffic; afterwards it is replaced
  by one `[rbtp] ...` line (`Port#replace_since`).
- Upstream quirk: after `FILE_ACK` the device opens the file and, if it cannot (bad directory), sends
  `ERROR` and ends the session at once, but the client already sends chunks, which land on the shell
  prompt as keystrokes (an STX in them can even start a new session that times out after 5 s). We
  cannot change the submodule, so after a failed transfer `Device.transfer` sends `\r` and waits until the
  prompt is back. A proper fix upstream: open the file before sending `FILE_ACK`.
- Measured on QEMU (UART): 20 KB up in 6.0 s, down in 3.6 s.

## QEMU

| tool | what it does |
|------|--------------|
| `qemu_start` | `rake qemu_serve` in Docker (or native), wait for the shell, connect the Port to it |
| `qemu_status` | running / building, tail of the rake output |
| `qemu_stop`  | stop the container (`docker stop`) |

Meant for checks that need no peripherals (logic, scripts under `/home`, boot checks).

### mrbgem helper (later)

`mrbgem_scaffold` (`mrbgem.rake`, `mrblib/`, `src/`) and adding a gem to `build_config/*.rb`.

## Shell interaction

The shell does line editing, so every keystroke is echoed with ANSI sequences
(`\e[1G$> echo\e[0K...`). `device_exec`:

1. strip ANSI sequences from the received stream,
2. write the command + `\r`,
3. read until the prompt `$> ` reappears (with timeout), drop the echoed command line.

## File transfer (RBTP / PicoModem)

Reference: `components/picoruby-esp32/picoruby/mrbgems/picoruby-picomodem` (README, `tools/picomodem.rb`).

- The existing host client runs on mruby and shells out to `stty`, so we reimplement it in CRuby
  on top of the Port (≈150 lines; CRC32 from `zlib`, CRC16/CCITT-FALSE hand-written).
- Frame: `STX | len(2, BE) | cmd | payload | CRC16(2, BE)`. Only `FILE_READ`/`FILE_WRITE`/`CHUNK`/`ABORT`
  exist, so `ls`/`rm` go through the shell, not RBTP.
- Sequence: shell at prompt → send `0x02` → wait for ACK `0x06` (skip other bytes) → wait ~200 ms →
  frames → read the trailing `[PicoModem] ...` line. The Port ring buffer must be paused
  (not parsed as shell output) while a transfer is in progress.
- Both directions are verified end to end with CRC32 (the device returns it in `DONE_ACK`).
- Implemented in `lib/r2p2_mcp/rbtp.rb` (`Channel`: frames over a read cursor on the Port buffer;
  `Session`: put / get). The binary traffic is replaced in the Port buffer by one `[rbtp] ...` line.
- Device quirk: after `FILE_ACK` the device opens the file and, if it cannot (bad directory), sends
  `ERROR` and ends the session at once. A `CHUNK` sent meanwhile would land on the shell prompt as
  keystrokes (its STX even starts a new session), so the client waits 150 ms for an early `ERROR`
  before the first chunk.
- Measured on QEMU (UART): 20 KB up in 5.2 s, down in 3.1 s.

## QEMU

Investigated 2026-10-04 with the existing `r2p2-esp32-idf:v5.5.4` image and `build-qemu/`.

- `idf.py qemu` (foreground) hard-codes `-serial mon:stdio`. The `mon:` multiplexer treats Ctrl-A
  (0x01) as an escape (`Ctrl-A x` quits QEMU), which would corrupt binary transfers over stdio. So
  we do not use stdio.
- **Implementation**: `rake qemu_serve` (rakelib/qemu.rake; `docker:qemu_serve` runs it in the
  container with a fixed container name and `-p 127.0.0.1:5555:5555`). It builds `build-qemu`
  (running `setup_qemu` and the eFuse step first if needed), regenerates `qemu_flash.bin` with
  `esptool merge_bin` like `idf.py qemu` does, then `exec`s `qemu-system-xtensa` with the arguments
  `idf.py qemu` prints, minus `-serial mon:stdio`, plus `-serial tcp:HOST:PORT,server,nowait`.
  It prints `[qemu_serve] ready ...` just before starting QEMU; `Qemu` (lib/r2p2_mcp/qemu.rb)
  waits for that marker, then retries connecting (Docker accepts on the published port before QEMU
  listens) until the shell prompt shows.
- Regenerating the flash image on every start gives a fresh `/home` per session (the guest used to
  modify the image in place), so there is no state to carry over or clean up.

Verified (manually, prototype scripts, not committed):

- Boot reaches `$> `, and `echo hello` works over the TCP socket from a host Ruby `TCPSocket`.
- **RBTP works over the QEMU UART console** (first checked with a throwaway client): uploading 3000 random bytes (containing 0x01/0x02)
  to `/home/rbtp_test.bin` finished with `DONE_ACK` status 0 and a matching CRC32.
- Observed: the first byte read after `0x02` was `\n`, not `0x06`, because the shell's prompt
  redraw was still in flight; the transfer succeeded anyway. The client must scan for `0x06`.

Measured: `qemu_start` takes about 25 s with an up-to-date `build-qemu` (incremental build + boot).

Still open:

- Docker on macOS (`-p` publishing works; file-sharing backend caveats in README apply).

## Milestones

1. **M1** `mcp/` skeleton, build tools (`setup`/`build`/`clean`, jobs)
2. **M2** Port + `device_exec`/`device_log`/`flash` on real hardware
3. **M3** RBTP `device_upload`/`device_download`
4. **M4** QEMU (`qemu_start`/`qemu_stop`)
5. **M5** mrbgem helper (done)

## Decisions made in M2

- Ring buffer: 256 KiB; `device_log` returns the last N lines (default 100), or only what is new with `since_last`.
- `flash` while connected to a `tcp://` port (QEMU) is an error. With a serial port it releases the port and reconnects after success (`reconnect`, default true).
- Console output goes through `Terminal.render` (cursor column + erase-to-EOL), not plain ANSI stripping, because the shell redraws the prompt on every keystroke.
- `device_exec` timeout: Ctrl-C, then Ctrl-D only while no prompt is showing (irb ignores Ctrl-C), so it never logs out the shell.

## Open questions

- Whether `device_eval` should use `irb` per call or keep one session.
- Real hardware is untested: DTR/RTS side effects of opening the port on boards with USB Serial/JTAG
  (may reset the board), and `flash` reconnect timing (fixed 2 s wait now).
