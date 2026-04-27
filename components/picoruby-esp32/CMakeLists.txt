set(PICORB_VM "mrubyc" CACHE STRING "Select build mode (mrubyc or mruby)")
message(STATUS "PICORB_VM is set to: ${PICORB_VM}")

file(MAKE_DIRECTORY ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/lib/mbedtls/include)

if(${PICORB_VM} STREQUAL "mruby")
  file(MAKE_DIRECTORY ${COMPONENT_DIR}/picoruby/build/esp32-picoruby/include)
  set(MRUBY_CONFIG_STRING "${COMPONENT_DIR}/build_config/${IDF_TARGET_ARCH}-esp-picoruby.rb")
  set(LIBMRUBY_PATH "esp32-picoruby")
  set(CUSTOM_TARGET_NAME "picoruby")
  set(ADDITIONAL_INCLUDE_DIRS
    ${COMPONENT_DIR}/picoruby/build/esp32-picoruby/include
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mruby/lib/mruby/include
  )
  set(ADDITIONAL_DEFINITIONS
    -DMRB_TICK_UNIT=10
    -DMRB_TIMESLICE_TICK_COUNT=1
    -DMRB_UTF8_STRING
    -DMRB_INT64=1
    -DMRB_NO_BOXING
    -DPICORB_VM_MRUBY
  )
else()
  file(MAKE_DIRECTORY ${COMPONENT_DIR}/picoruby/build/esp32-femtoruby/mrbgems)
  set(MRUBY_CONFIG_STRING "${COMPONENT_DIR}/build_config/${IDF_TARGET_ARCH}-esp-femtoruby.rb")
  set(LIBMRUBY_PATH "esp32-femtoruby")
  set(CUSTOM_TARGET_NAME "picoruby")
  set(ADDITIONAL_INCLUDE_DIRS
    ${COMPONENT_DIR}/picoruby/build/esp32-femtoruby/mrbgems
  )
  set(ADDITIONAL_DEFINITIONS
    -DMRBC_TICK_UNIT=10
    -DMRBC_TIMESLICE_TICK_COUNT=1
    -DMRBC_USE_FLOAT=2
    -DMRC_CUSTOM_ALLOC
    -DPICORB_VM_MRUBYC
  )
endif()

if(CONFIG_ESP_WIFI_ENABLED)
  list(APPEND ADDITIONAL_DEFINITIONS -DCONFIG_ESP_WIFI_ENABLED)
endif()

idf_component_register(
  SRCS
    ${COMPONENT_DIR}/picoruby-esp32.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-esp32/ports/esp32.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-machine/ports/esp32/machine.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-machine/ports/common/machine.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-io-console/ports/esp32/io-console.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-filesystem-fat/ports/esp32/flash_disk.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-littlefs/ports/esp32/flash_hal.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-env/ports/esp32/env.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-gpio/ports/esp32/gpio.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-adc/ports/esp32/adc.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-spi/ports/esp32/spi.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-rng/ports/esp32/rng.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-pwm/ports/esp32/pwm.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-rmt/ports/esp32/rmt.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-watchdog/ports/esp32/watchdog.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/ports/esp32/timing_alt.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/ports/common/cipher.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/ports/common/cmac.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/ports/common/digest.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/ports/common/hmac.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/ports/common/pkey.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/ports/common/md.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-socket/ports/esp32/net_helpers.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-socket/ports/esp32/ssl_socket.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-socket/ports/esp32/tcp_server.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-socket/ports/esp32/tcp_socket.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-socket/ports/esp32/udp_socket.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-i2c/ports/esp32/i2c.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-uart/ports/esp32/uart.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-require/ports/esp32/platform.c
  INCLUDE_DIRS
    ${COMPONENT_DIR}
    ${COMPONENT_DIR}/picoruby/include
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mrubyc/lib/mrubyc/src
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-machine/include
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/include
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/lib/mbedtls/include
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-filesystem-fat/ports/esp32
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-littlefs/ports/esp32
    ${COMPONENT_DIR}/picoruby/mrbgems/mruby-compiler2/include
    ${COMPONENT_DIR}/picoruby/mrbgems/mruby-compiler2/lib/prism/include
    ${ADDITIONAL_INCLUDE_DIRS}
  PRIV_REQUIRES
    esp_driver_gpio
    esp_driver_uart
    esp_driver_spi
    esp_driver_ledc
    esp_driver_rmt
    esp_driver_i2c
    esp_adc
    esp_timer
    esp_hw_support
    spi_flash
    nvs_flash
    esp_wifi
    esp_psram
    esp_driver_usb_serial_jtag
)

add_definitions(
  ${ADDITIONAL_DEFINITIONS}
  -DMRBC_CONVERT_CRLF=1
  -DUSE_FAT_FLASH_DISK
  -DESP32_PLATFORM
  -DNDEBUG
)

set(PICORUBY_DIR ${COMPONENT_DIR}/picoruby)
set(LIBMRUBY_FILE ${PICORUBY_DIR}/build/${LIBMRUBY_PATH}/lib/libmruby.a)

# Expose sdkconfig values to build config via env vars
set(MRUBY_ENV
  MRUBY_CONFIG=${MRUBY_CONFIG_STRING}
  CONFIG_IDF_TARGET=${CONFIG_IDF_TARGET}
  CONFIG_ESP_WIFI_ENABLED=${CONFIG_ESP_WIFI_ENABLED}
)

# Build PicoRuby
add_custom_command(
  OUTPUT ${LIBMRUBY_FILE}
  COMMAND ${CMAKE_COMMAND} -E echo ${MRUBY_ENV} rake
  COMMAND ${CMAKE_COMMAND} -E env ${MRUBY_ENV} rake
  WORKING_DIRECTORY ${PICORUBY_DIR}
  COMMENT "PicoRuby build"
  VERBATIM
)

add_prebuilt_library(
  libmruby ${LIBMRUBY_FILE}
  REQUIRES ${COMPONENT_NAME}
)
target_link_libraries(${COMPONENT_LIB} PRIVATE libmruby)
target_include_directories(
  ${COMPONENT_LIB}
  PRIVATE
    ${COMPONENT_DIR}/picoruby/mrbgems/mruby-compiler2/include
    ${COMPONENT_DIR}/picoruby/mrbgems/mruby-compiler2/lib/prism/include
    ${ADDITIONAL_INCLUDE_DIRS}
)

add_custom_target(
  ${CUSTOM_TARGET_NAME} DEPENDS ${LIBMRUBY_FILE}
)
add_dependencies(${COMPONENT_LIB} ${CUSTOM_TARGET_NAME})

# Compile Ruby files
set(RUBY_FILES main_task)
set(PICORBC ${COMPONENT_DIR}/picoruby/bin/picorbc)
set(GENERATED_C_FILES "")

foreach(rb ${RUBY_FILES})
  set(C_FILE ${COMPONENT_DIR}/mrb/${rb}.c)
  set(RB_FILE ${COMPONENT_DIR}/mrblib/${rb}.rb)
  add_custom_command(
    OUTPUT ${C_FILE}
    COMMAND ${CMAKE_COMMAND} -E echo "Compiling ${RB_FILE}..."
    COMMAND ${CMAKE_COMMAND} -E make_directory ${COMPONENT_DIR}/mrb
    COMMAND ${PICORBC} -B${rb} -o${C_FILE} ${RB_FILE}
    DEPENDS ${CUSTOM_TARGET_NAME} ${RB_FILE}
    COMMENT "Compiling ${RB_FILE}"
    VERBATIM
  )
  list(APPEND GENERATED_C_FILES ${C_FILE})
endforeach(rb)

target_sources(${COMPONENT_LIB} PRIVATE ${GENERATED_C_FILES})
