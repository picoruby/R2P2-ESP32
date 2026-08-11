# R2P2-ESP32

This project runs [R2P2](https://github.com/picoruby/R2P2) (Ruby Rapid Portable Platform), a [PicoRuby](https://github.com/picoruby/picoruby) shell, on ESP32.

## Getting Started

If this is your first time running PicoRuby on an ESP32, you can get up and running quickly with just a few steps!

### Flashing the Firmware

1. Prepare your device and connect it to your PC via USB (see [Supported Devices](#supported-devices))
2. Visit the [R2P2-ESP32 Web Installer](https://picoruby.org/R2P2-ESP32-installer/) (Chrome, Edge, or Opera required)
3. Select your target and VM, then click "Connect and Flash"
4. After flashing, open the [R2P2 Web Terminal](https://picoruby.org/terminal) and click "Connect" to access the `picoruby-shell`

### Launching irb

Once the `picoruby-shell` prompt appears, type `irb` to start a REPL directly on your device.

```text
$> irb
irb> 1 + 2
=> 3
irb> words = ["Hello", "PicoRuby", "!"]
=> ["Hello", "PicoRuby", "!"]
irb> words.join(" ")
=> "Hello PicoRuby !"
irb>
```

### Uploading and Running a Program

In the "File Editor" panel of the [R2P2 Web Terminal](https://picoruby.org/terminal), write a program like this:

```ruby
words = ["Hello", "PicoRuby", "!"]
puts words.join(" ")
```

Change the path from `/home/app.rb` to `/home/hello.rb` and click "Upload" to write the file to your device.
You can then run it with:

```text
$> ls
hello.rb
$> ./hello.rb
Hello PicoRuby !
$>
```

For available classes and features, see [PicoRuby.org](https://picoruby.org/index.html).

### Other Shell Commands

`picoruby-shell` comes with a variety of built-in commands:

```text
$> echo 'Hello!'
Hello!
$> cat hello.rb
words = ["Hello", "PicoRuby", "!"]
puts words.join(" ")
$> mkdir 'tmp'
$> cd 'tmp'
$> pwd
/home/tmp
$> reboot
```

See [here](https://github.com/picoruby/picoruby/tree/master/mrbgems/picoruby-shell/shell_executables) for the full list of available commands.

## Setting Up a Development Environment

You will need to set up a development environment if you want to:

- Add or remove mrbgems
- Write and include your own custom mrbgem
- Contribute to [PicoRuby](https://github.com/picoruby/picoruby) or [R2P2-ESP32](https://github.com/picoruby/R2P2-ESP32)
- Expand heap space or enable PSRAM support
- Meet any other requirement not covered by the pre-built firmware images

### Prerequisites

Set up your development environment using ESP-IDF by referring to [this page](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/index.html#installation). The build has been verified with ESP-IDF v5.5.

### Getting the Source

Clone the repository with all submodules:

```sh
$ git clone --recursive https://github.com/picoruby/R2P2-ESP32.git
```

### Hardware-specific Configuration

Some hardware variants require additional configuration via the `SDKCONFIG_DEFAULTS` environment variable.
Fragment files for each option are provided under `sdkconfigs/`.
You can combine them as needed by appending fragment file paths separated by semicolons.

Here are some examples:

**When using USB console** (boards without an external USB-to-UART chip):

```sh
$ export SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfigs/usb_console"
```

**When using USB console with SPIRAM:**

```sh
$ export SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfigs/usb_console;sdkconfigs/spiram"
```

Set the environment variable before running `rake setup_*` and `rake build`.
If you change `SDKCONFIG_DEFAULTS`, delete the `sdkconfig` file and rebuild from scratch.

### Build

Run the setup task for your target (first time only):

```sh
$ cd R2P2-ESP32

# Activate ESP-IDF (replace x with your patch version, e.g. 4)
$ source ~/.espressif/tools/activate_idf_v5.5.x.sh
$ export PATH="$IDF_PATH/tools:$PATH"
```

After activation, add Ruby to PATH using your version manager:

```sh
# mise:
$ mise use ruby@4.0.5
# asdf:
$ asdf local ruby 4.0.5
# rbenv:
$ rbenv local 4.0.5
```

> **Note:** The setup task builds some host-side tools with the host (non-cross) toolchain. It is detected automatically even while ESP-IDF's cross toolchains are on PATH. If the detection picks a wrong compiler or archiver, override it with the `HOST_CC` / `HOST_AR` environment variables.

> **Tip:** You can manage the above environment variables in a `.envrc` file using [direnv](https://direnv.net/), so they are applied automatically whenever you enter the project directory.

```
source ~/.espressif/tools/activate_idf_v5.5.4.sh
PATH_add "$IDF_PATH/tools"
```

```sh
# Setup (first time only)
$ rake setup_esp32   # if you use esp32
$ rake setup_esp32c3 # if you use esp32c3
$ rake setup_esp32c6 # if you use esp32c6
$ rake setup_esp32h2 # if you use esp32h2
$ rake setup_esp32p4 # if you use esp32p4
$ rake setup_esp32s3 # if you use esp32s3

# Build
$ rake build
```

PicoRuby currently supports two VMs. Run the build task for the one you want to use:

```sh
# PicoRuby (VM: mruby)
rake picoruby:build

# FemtoRuby (VM: mruby/c)
rake femtoruby:build
```

See [Supported Devices](#supported-devices) for which VMs are available for each device.

### Building with Docker

Instead of installing ESP-IDF, Ruby, and a host toolchain locally, you can build entirely inside
a container based on the official [`espressif/idf`](https://hub.docker.com/r/espressif/idf) image,
which already bundles ESP-IDF, `gcc`, and `ruby`. `docker/Dockerfile` adds the couple of packages
that image is missing for a PicoRuby build (`ruby-dev`, `libssl-dev`) on top of it; `rake docker:*`
tasks build that image automatically the first time you use them.

Requirements: Docker and the submodules checked out locally (`git submodule update --init
--recursive`, see [Getting the Source](#getting-the-source)).

The project directory is bind-mounted into the container, so your host's Docker file-sharing
backend needs to handle symlinks correctly (it has to read and create files through the symlinks
vendored under `components/picoruby-esp32/picoruby`). **On macOS, `virtiofs` must be enabled** --
other backends (Docker Desktop's `gRPC FUSE`/`osxfs`, Rancher Desktop's `reverse-sshfs`/9p) fail
with `Operation not permitted`.

Every `docker:*` task runs the equivalently-named task (`docker:setup_esp32s3` → `rake
setup_esp32s3`, `docker:picoruby:build` → `rake picoruby:build`, etc.) inside the container, so it
behaves like the native build:

```sh
# Setup (first time only)
$ rake docker:setup_esp32s3   # or docker:setup_esp32, docker:setup_esp32c3, ...

# Build
$ rake docker:build
$ rake docker:picoruby:build  # or docker:femtoruby:build

# Run on QEMU (ESP32-S3), no hardware required
$ rake docker:setup_qemu
$ rake docker:picoruby:qemu   # or docker:femtoruby:qemu, docker:qemu

# Ad-hoc shell in the container
$ rake docker:shell
```

Unlike the native build, `docker:*` tasks don't read `SDKCONFIG_DEFAULTS`/`USE_WIFI`/etc. from
your shell -- put them in a gitignored `.env` file at the project root instead (`docker:*` tasks
pass it to the container as-is if it exists). Docker's `--env-file` format doesn't strip quotes
the way a shell does, so **don't quote the value**:

```sh
# .env
SDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfigs/usb_console
```

To use a different ESP-IDF patch version than the pinned default (`v5.5.4`, see `DOCKER_IDF_TAG` in
`rakelib/docker.rake`), set `ESP_IDF_DOCKER_TAG` (any tag from the
[image's tag list](https://hub.docker.com/r/espressif/idf/tags)):

```sh
$ export ESP_IDF_DOCKER_TAG=v5.5.5
$ rake docker:build
```

Gems (`bundle install`) and ccache output are cached in `.bundle-docker`/`.ccache` under the
project root (gitignored) so they persist between runs. If you've also built natively on the host,
`docker:*` tasks automatically detect and rebuild a stale host-arch (e.g. macOS Mach-O) `mrbc` left
under `components/picoruby-esp32/picoruby/build` -- otherwise it would look "already built" and
fail to link with "file format not recognized". `rake docker:reset` clears the gem/ccache caches
for a clean slate if they ever end up in a bad state.

> **Note:** There's no `docker:flash`/`docker:monitor` task, because most container setups (e.g.
> Docker Desktop, Rancher Desktop on macOS/Windows) can't pass the device's serial port through to
> the container at all -- it's not a Dockerfile/CLI-flag issue, the port simply isn't visible
> inside their Linux VM. Flash/monitor the image built by `docker:build` from the host instead
> with `rake flash`/`rake monitor` (see [Flash and Monitor](#flash-and-monitor)) -- these don't
> need a full ESP-IDF install either. On native Linux, `docker run --device=/dev/ttyUSB0 ...` can
> pass a serial device through if you want to flash from inside a container too.

### Enabling WiFi (`USE_WIFI`)

WiFi native code (`Network::WiFi` / `ESP32::WiFi`, and by extension `picoruby-socket`'s
`TCPServer`/`TCPSocket` over WiFi) is **not** compiled in by default. To enable it, set the
`USE_WIFI` environment variable before building:

```sh
$ export USE_WIFI=1
$ rake build
```

This is required, for example, to use [picoruby-debug](https://github.com/yuuu/picoruby-debug)'s
DAP remote debugging over WiFi.

> **Note:** `USE_WIFI` is only read while CMake configures the project, not on every build. If
> you already ran `rake setup_*` or `rake build` without `USE_WIFI` set, a plain
> `USE_WIFI=1 rake build` will not pick it up and can fail with linker errors such as
> `undefined reference to 'ESP32_WIFI_init'`. Force a reconfigure first:
>
> ```sh
> $ export USE_WIFI=1
> $ idf.py reconfigure
> $ rake build
> ```
>
> Alternatively, run `rake setup_*` again with `USE_WIFI=1` already exported.

### Flash and Monitor

`rake flash`/`rake monitor` call `esptool`/`esp-idf-monitor` directly rather than `idf.py`, so
they work from a `build/` produced by [Docker](#building-with-docker) too, without a full
ESP-IDF install on the host -- just `pip install esptool esp-idf-monitor`.

Flash the built image to your device:

```sh
$ rake flash
```

Open a serial terminal to connect to your device:

```sh
$ rake monitor
```

If the serial port isn't auto-detected correctly (e.g. multiple devices connected), set `PORT`:

```sh
$ PORT=/dev/tty.usbserial-0001 rake flash
```

### Running on QEMU (ESP32-S3)

R2P2-ESP32 can be run under [QEMU](https://github.com/espressif/qemu) targeting ESP32-S3, without any real hardware. This uses ESP-IDF's built-in `idf.py qemu` support and the `qemu-xtensa` tool package (`idf_tools.py install qemu-xtensa`).

Set up a separate build directory (`build-qemu`) once, targeting ESP32-S3 with a UART console (QEMU does not emulate the USB Serial/JTAG console):

```sh
$ rake setup_qemu
```

Then run it with the VM of your choice:

```sh
$ rake femtoruby:qemu # VM: mruby/c
$ rake picoruby:qemu  # VM: mruby
$ rake qemu           # whichever VM is currently configured in build-qemu (defaults to femtoruby/mrubyc)
```

This drops you into the `picoruby-shell` prompt over the emulated UART. Use `Ctrl-A X` to quit QEMU (`-nographic` mode).

**Known QEMU limitations:**

- **USB Serial/JTAG console is not emulated.** `rake setup_qemu` builds with `sdkconfigs/qemu` (UART console) regardless of your usual `SDKCONFIG_DEFAULTS`, since a USB Serial/JTAG console build hangs forever waiting for a host connection that QEMU never provides.
- **ADC/SENS peripherals are not emulated**, so the ADC hardware self-calibration that normally runs before `app_main` spins forever. `rake qemu` works around this by burning `BLK_VERSION_MAJOR=1` into the QEMU eFuse image the first time it runs, which makes calibration read from (zeroed) eFuse data instead of touching the hardware. ADC readings under QEMU are therefore not meaningful.
- **PSRAM is capped at 8MB** (`--qemu-extra-args='-m 8M'`) even though the real hardware may have more. With the default 32MB, QEMU cannot map the full PSRAM into the virtual address space, and mounting the `storage` (littlefs) partition then crashes with `esp_mmu_map: no such vaddr range`.
- `USE_WIFI` builds still compile, but QEMU only emulates an Ethernet MAC (`open_eth`), not real WiFi hardware, so `Network::WiFi` / `ESP32::WiFi` won't work under QEMU.

## Supported Devices

The following devices have been confirmed to work:

| Device | Target | VM | USB Console | SPIRAM |
|--------|--------|----|-------------|--------|
| ESP32-DevKitC | ESP32 | FemtoRuby (mruby/c) | No | No |
| ATOM Matrix | ESP32 | FemtoRuby (mruby/c) | No | No |
| M5Stamp C3 Mate | ESP32-C3 | FemtoRuby (mruby/c) | No | No |
| ESPr® Developer S3 Type-C | ESP32-S3 | FemtoRuby (mruby/c), PicoRuby (mruby) | No | Yes |
| ATOMS3 Lite | ESP32-S3 | FemtoRuby (mruby/c), PicoRuby (mruby) | Yes | No |
| M5Stack CoreS3 | ESP32-S3 | FemtoRuby (mruby/c), PicoRuby (mruby) | Yes | Yes |

## License

[R2P2-ESP32](https://github.com/picoruby/R2P2-ESP32.git) is released under the [MIT License](https://github.com/picoruby/R2P2-ESP32/blob/master/LICENSE).
