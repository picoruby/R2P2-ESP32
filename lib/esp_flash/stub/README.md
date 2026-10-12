# Flasher stubs

`EspFlash::Loader` uploads one of these into the chip's RAM and runs it in place of the ROM loader:
it writes the flash faster (16 KB blocks, erasing as it writes) and computes MD5s faster.

The JSON files are the binaries of [esp-flasher-stub](https://github.com/espressif/esp-flasher-stub)
v1.2.2 as released at https://github.com/espressif/esp-flasher-stub/releases/tag/v1.2.2 (and shipped
with esptool 5 in `esptool/targets/stub_flasher/2/`), where the sources can be obtained. They are dual
licensed under the Apache License Version 2.0 (`LICENSE-APACHE`) or the MIT license (`LICENSE-MIT`).
