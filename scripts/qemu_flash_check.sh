#!/usr/bin/env bash
# Flash R2P2-ESP32 into a blank flash through the ESP32-S3 ROM serial loader with lib/esp_flash (what
# `rake flash` uses), on QEMU started in the download mode with its UART on TCP; then boot that flash
# and verify it reaches the picoruby-shell prompt.
#
# Usage: qemu_flash_check.sh   (after qemu_boot_check.sh, which builds build-qemu and its eFuse image)
set -uo pipefail

BUILD_DIR="${QEMU_BUILD_DIR:-build-qemu}"
PORT="${QEMU_FLASH_PORT:-5560}"
LOGFILE="qemu-boot-flashed.log"
BOOT_TIMEOUT="${QEMU_BOOT_TIMEOUT:-300}"
WORK="$(mktemp -d)"
FLASH="$WORK/flash.bin"

QEMU_COMMON=(-M esp32s3 -nographic -monitor none -drive "file=$FLASH,if=mtd,format=raw")

ruby -Ilib -resp_flash -rjson -e '
  size = JSON.parse(File.read(File.join(ARGV[0], "flasher_args.json"))).dig("flash_settings", "flash_size")
  File.binwrite(ARGV[1], "\xff".b * EspFlash.parse_size(size))' "$BUILD_DIR" "$FLASH" || exit 1

echo "== Starting QEMU in the download mode (UART on tcp://127.0.0.1:${PORT}) =="
qemu-system-xtensa "${QEMU_COMMON[@]}" -global driver=esp32s3.gpio,property=strap_mode,value=0x07 \
  -serial "tcp:127.0.0.1:${PORT},server,nowait" &
QEMU_PID=$!
sleep 3

echo "== Flashing ${BUILD_DIR} with lib/esp_flash =="
ruby -Ilib -resp_flash -rjson -e '
  args = JSON.parse(File.read(File.join(ARGV[0], "flasher_args.json")))
  loader = EspFlash::Loader.open(ARGV[1], chip: "esp32s3",
                                          flash_size: EspFlash.parse_size(args.dig("flash_settings", "flash_size")))
  args["flash_files"].sort_by { |addr, _file| Integer(addr, 16) }.each do |addr, file|
    loader.write_flash(Integer(addr, 16), File.binread(File.join(ARGV[0], file)), name: file)
  end
  loader.close' "$BUILD_DIR" "socket://127.0.0.1:${PORT}"
flashed=$?
kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
[ "$flashed" -eq 0 ] || { echo "== Flashing failed =="; exit 1; }

echo "== Booting the flashed image =="
qemu-system-xtensa "${QEMU_COMMON[@]}" -m 8M \
  -drive "file=$BUILD_DIR/qemu_efuse.bin,if=none,format=raw,id=efuse" \
  -global driver=nvram.esp32s3.efuse,property=drive,value=efuse \
  -global driver=timer.esp32s3.timg,property=wdt_disable,value=true \
  -global driver=ssi_psram,property=is_octal,value=true \
  -serial "file:$LOGFILE" &
QEMU_PID=$!

result=1
for _ in $(seq 1 "$BOOT_TIMEOUT"); do
  if grep -q '\$> ' "$LOGFILE" 2>/dev/null; then
    echo "== Shell prompt reached =="
    result=0
    break
  fi
  kill -0 "$QEMU_PID" 2>/dev/null || break
  sleep 1
done
[ "$result" -eq 0 ] || echo "== The flashed image did not reach the shell prompt =="

echo "---- ${LOGFILE} ----"
cat "$LOGFILE" 2>/dev/null
echo "---------------------"

kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
rm -rf "$WORK"
exit "$result"
