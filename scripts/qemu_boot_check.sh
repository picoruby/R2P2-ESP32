#!/usr/bin/env bash
# Boot R2P2-ESP32 on QEMU (ESP32-S3) and verify it reaches the picoruby-shell prompt.
#
# Usage: qemu_boot_check.sh <mrubyc|mruby>
#
# Works around QEMU limitations discussed in README.md's "Running on QEMU"
# section: UART console (sdkconfigs/qemu), ADC calibration eFuse bypass, and
# capped PSRAM. Runs standalone (no rake/Ruby dependency) so it can run
# inside the espressif/idf Docker image used by CI.
set -uo pipefail

VM="${1:?Usage: $0 <mrubyc|mruby>}"
BUILD_DIR="${QEMU_BUILD_DIR:-build-qemu}"
LOGFILE="qemu-boot-${VM}.log"
BOOT_TIMEOUT="${QEMU_BOOT_TIMEOUT:-300}"

SUCCESS_PATTERN='\$> '
FAILURE_PATTERN='assert failed|no such vaddr|Guru Meditation|calibration efuse version does not match|Rebooting\.\.\.'

echo "== Configuring ${BUILD_DIR} (PICORB_VM=${VM}) =="
idf.py -B "$BUILD_DIR" \
  -D SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfigs/qemu" \
  -D SDKCONFIG="$BUILD_DIR/sdkconfig" \
  -D PICORB_VM="$VM" \
  set-target esp32s3

EFUSE_PATH="$BUILD_DIR/qemu_efuse.bin"
if [ ! -f "$EFUSE_PATH" ]; then
  echo "== Burning ADC calibration eFuse (BLK_VERSION_MAJOR=1) =="
  idf.py -B "$BUILD_DIR" qemu efuse-burn --do-not-confirm BLK_VERSION_MAJOR 1
fi

echo "== Building and booting QEMU =="
idf.py -B "$BUILD_DIR" qemu --qemu-extra-args='-m 8M' > "$LOGFILE" 2>&1 &
QEMU_JOB_PID=$!

result=1
elapsed=0
while [ "$elapsed" -lt "$BOOT_TIMEOUT" ]; do
  if grep -qE "$SUCCESS_PATTERN" "$LOGFILE" 2>/dev/null; then
    echo "== Shell prompt reached =="
    result=0
    break
  fi
  if grep -qE "$FAILURE_PATTERN" "$LOGFILE" 2>/dev/null; then
    echo "== Failure pattern detected in boot log =="
    result=1
    break
  fi
  if ! kill -0 "$QEMU_JOB_PID" 2>/dev/null; then
    echo "== idf.py qemu exited before reaching the shell prompt =="
    result=1
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

if [ "$elapsed" -ge "$BOOT_TIMEOUT" ] && [ "$result" -ne 0 ]; then
  echo "== Timed out after ${BOOT_TIMEOUT}s waiting for the shell prompt =="
fi

echo "---- ${LOGFILE} ----"
cat "$LOGFILE" 2>/dev/null
echo "---------------------"

pkill -f qemu-system-xtensa 2>/dev/null || true
kill "$QEMU_JOB_PID" 2>/dev/null || true
wait "$QEMU_JOB_PID" 2>/dev/null || true

exit "$result"
