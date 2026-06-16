# components/btstack/CMakeLists.txt
# Wraps the BTstack source vendored at picoruby/picoruby/mrbgems/picoruby-r2p2/lib/pico-sdk/lib/btstack/

set(BTSTACK_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../picoruby-esp32/picoruby/mrbgems/picoruby-r2p2/lib/pico-sdk/lib/btstack")

# Core BTstack sources required for BLE peripheral
file(GLOB BTSTACK_SRC_CORE
    "${BTSTACK_ROOT}/src/*.c"
    "${BTSTACK_ROOT}/src/ble/*.c"
    "${BTSTACK_ROOT}/src/ble/gatt-service/*.c"
)

# Exclude classic-only sources (we have BLE only target)
set(EXCLUDE_PATTERNS
    "btstack_audio_embedded"
    "btstack_chipset_"
    "btstack_signal"
    "hci_dump_posix_fs"
    "hci_dump_segger_rtt_stdout"
    "hci_dump_posix_stdout"
    "hci_transport_h2_libusb"
    "hci_transport_h4"
    "hci_transport_h5"
    "hci_transport_em9304_spi"
    "btstack_chipset_em9301"
    "wav_util"
    "btstack_lc3"
    "hci_dump_segger_rtt_binary"
)

foreach(pattern ${EXCLUDE_PATTERNS})
    list(FILTER BTSTACK_SRC_CORE EXCLUDE REGEX ".*${pattern}.*")
endforeach()

# ESP32-specific port
set(BTSTACK_SRC_ESP32
    "${BTSTACK_ROOT}/port/esp32/components/btstack/btstack_port_esp32.c"
    "${BTSTACK_ROOT}/port/esp32/components/btstack/btstack_tlv_esp32.c"
    "${BTSTACK_ROOT}/platform/freertos/btstack_run_loop_freertos.c"
    "${BTSTACK_ROOT}/platform/embedded/hci_dump_embedded_stdout.c"
)

idf_component_register(
    SRCS ${BTSTACK_SRC_CORE} ${BTSTACK_SRC_ESP32}
    INCLUDE_DIRS
        "."
        "${BTSTACK_ROOT}/src"
        "${BTSTACK_ROOT}/src/ble"
        "${BTSTACK_ROOT}/src/ble/gatt-service"
        "${BTSTACK_ROOT}/3rd-party/micro-ecc"
        "${BTSTACK_ROOT}/3rd-party/bluedroid/decoder/include"
        "${BTSTACK_ROOT}/3rd-party/bluedroid/encoder/include"
        "${BTSTACK_ROOT}/platform/freertos"
        "${BTSTACK_ROOT}/platform/embedded"
        "${BTSTACK_ROOT}/port/esp32/components/btstack"
        "${BTSTACK_ROOT}/port/esp32/components/btstack/include"
        # ESP-IDF v5.x moved FreeRTOS.h under freertos/ subdir; BTstack port still
        # uses bare `#include "FreeRTOS.h"` (v4.x style), so expose the inner dir.
        "$ENV{IDF_PATH}/components/freertos/FreeRTOS-Kernel/include/freertos"
        "$ENV{IDF_PATH}/components/freertos/esp_additions/include/freertos"
    REQUIRES bt nvs_flash freertos
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-unused-variable -Wno-unused-function -Wno-format)
