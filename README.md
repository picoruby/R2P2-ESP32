# R2P2-ESP32

This project runs [PicoRuby](https://github.com/picoruby/picoruby) on ESP32 and serves as an example of using [picoruby-esp32](https://github.com/picoruby/picoruby-esp32).  
Currently, **it has only been tested on the [M5Stamp C3 Mate](https://docs.m5stack.com/ja/core/stamp_c3).**

## Getting Started

### Preparation

Set up your development environment using ESP-IDF by referring to [this page](https://docs.espressif.com/projects/esp-idf/en/v5.4/esp32/get-started/index.html#manual-installation).

### Setup

Run the following shell script to build PicoRuby:

```sh
$ git clone https://github.com/picoruby/R2P2-ESP32.git

$ cd R2P2-ESP32
$ ./components/picoruby-esp32/install.sh
```

If you want to use several files on a device, store them under `./storage/home` .
The file named `app.mrb` or `app.rb` is automatically executed after device startup.

#### Looking for Contributors

I would like to enable the device to be recognized as a USB Mass Storage Class when connected to a PC, allowing files to be written via drag-and-drop, similar to R2P2.  
If you are interested in contributing, feel free to submit a pull request or open an issue!

### Build

Build the project using the `idf.py` command.

```sh
$ . $(YOUR_ESP_IDF_PATH)/export.sh
$ idf.py set-target $(YOUR_ESP_TARGET) # example: idf.py set-target esp32c3
$ idf.py build
```

### Flash and Monitor

Flash the firmware and monitor the output using the `idf.py` command. PicoRuby Shell will start.

```sh
$ idf.py flash
$ idf.py monitor
```

## Supported Environment

Currently, this project is tested in the following environment only:

- **Build OS**:
  - macOS
- **Device**:
  - ESP32-DevKitC(esp32)
  - M5Stamp C3 Mate(esp32c3)

## License

[R2P2-ESP32](https://github.com/picoruby/R2P2-ESP32.git) is released under the [MIT License](https://github.com/picoruby/R2P2-ESP32/blob/master/LICENSE).
