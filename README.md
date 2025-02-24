# R2P2-ESP32

This project runs [R2P2](https://github.com/picoruby/R2P2) (Ruby Rapid Portable Platform) on ESP32.
It uses [picoruby-esp32](https://github.com/picoruby/picoruby-esp32), a component to run [PicoRuby](https://github.com/picoruby/picoruby) on ESP32.


## Getting Started

### Preparation

Set up your development environment using ESP-IDF by referring to [this page](https://docs.espressif.com/projects/esp-idf/en/v5.4/esp32/get-started/index.html#manual-installation).

### Setup

Run the following shell script to build PicoRuby:

```sh
$ git clone https://github.com/picoruby/R2P2-ESP32.git
```

If you want to use several files on a device, store them under `./storage/home` .
The file named `app.mrb` or `app.rb` is automatically executed after device startup.

#### Looking for Contributors

I would like to enable the device to be recognized as a USB Mass Storage Class when connected to a PC, allowing files to be written via drag-and-drop, similar to R2P2.  
If you are interested in contributing, feel free to submit a pull request or open an issue!

### Build

Build the project using the `idf.py` command.

```sh
$ cd R2P2-ESP32
$ . $(YOUR_ESP_IDF_PATH)/export.sh

# Setup(First time only)
$ rake setup_esp32   # if you use esp32
$ rake setup_esp32c3 # if you use esp32c3

# Build
$ rake build
```

### Flash and Monitor

Flash the firmware and monitor the output using the `idf.py` command. PicoRuby Shell will start.

```sh
# Flash
$ rake flash

# Monitor
$ rake monitor
```

If you want to run `build` -> `flash` -> `monitor` , you can use `rake` .

```sh
# Build -> Flash -> Monitor
$ rake
```

## Supported Environment

Currently, this project is tested in the following environment only:

- **Build OS**:
  - Linux
  - macOS
- **Device**:
  - ESP32-DevKitC(esp32)
  - M5Stamp C3 Mate(esp32c3)

## License

[R2P2-ESP32](https://github.com/picoruby/R2P2-ESP32.git) is released under the [MIT License](https://github.com/picoruby/R2P2-ESP32/blob/master/LICENSE).
