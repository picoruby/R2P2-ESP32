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

Set up your development environment using ESP-IDF by referring to [this page](https://docs.espressif.com/projects/esp-idf/en/release-v5.5/esp32/get-started/index.html#manual-installation).

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
```

After activation, add Ruby to PATH using your version manager:

```sh
# mise:
$ export PATH="$HOME/.local/share/mise/shims:$PATH"
# asdf:
$ export PATH="$HOME/.asdf/shims:$PATH"
# rbenv:
$ export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
```

Set the C compiler (`CC`) and Archiver (`AR`) to the host toolchain.
ESP-IDF's activation script may override these with cross-compilers.

```sh
# macOS:
$ export CC=/usr/bin/cc
$ export AR=/usr/bin/ar
# Linux:
$ export CC=/usr/bin/gcc
$ export AR=/usr/bin/ar
```

> **Tip:** You can manage all of the above environment variables in a `.envrc` file using [direnv](https://direnv.net/), so they are applied automatically whenever you enter the project directory.

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

### Flash and Monitor

Flash the built image to your device:

```sh
$ rake flash
```

Open a serial terminal to connect to your device:

```sh
$ rake monitor
```

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
