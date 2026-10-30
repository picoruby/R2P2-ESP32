set(PICORB_VM "mrubyc" CACHE STRING "Select build mode (mrubyc or mruby)")
message(STATUS "PICORB_VM is set to: ${PICORB_VM}")

file(MAKE_DIRECTORY ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/lib/mbedtls/include)
file(MAKE_DIRECTORY ${COMPONENT_DIR}/picoruby/build/prism/include)

if(${PICORB_VM} STREQUAL "mruby")
  file(MAKE_DIRECTORY ${COMPONENT_DIR}/picoruby/build/esp32-picoruby/include)
  set(MRUBY_CONFIG_STRING "${COMPONENT_DIR}/build_config/${IDF_TARGET_ARCH}-esp-picoruby.rb")
  set(LIBMRUBY_PATH "esp32-picoruby")
  set(CUSTOM_TARGET_NAME "picoruby")
  set(ADDITIONAL_INCLUDE_DIRS
    ${COMPONENT_DIR}/picoruby/build/esp32-picoruby/include
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mruby/lib/mruby/include
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-task/include
  )
  set(ADDITIONAL_DEFINITIONS
    -DMRB_TICK_UNIT=10
    -DMRB_TIMESLICE_TICK_COUNT=1
    -DMRB_UTF8_STRING
    # Must match build_config/*-esp-picoruby.rb: these fix sizeof(mrb_value)
    # and the mrb_state layout shared with libmruby.
    -DMRB_INT32=1
    -DMRB_WORD_BOXING=1
    -DMRB_32BIT=1
    -DPICORB_ALLOC_ESTALLOC
    -DPICORB_ALLOC_ALIGN=8
    -DPICORB_VM_MRUBY
    -DMRB_USE_TASK_SCHEDULER
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

if(CONFIG_ESP_WIFI_ENABLED AND DEFINED ENV{USE_WIFI})
  list(APPEND ADDITIONAL_DEFINITIONS -DUSE_WIFI)
  set(MRUBY_USE_WIFI $ENV{USE_WIFI})
endif()

if(DEFINED ENV{HEAP_SIZE})
  list(APPEND ADDITIONAL_DEFINITIONS -DHEAP_SIZE=$ENV{HEAP_SIZE})
endif()

if(DEFINED ENV{PICORB_TASK_STACK_SIZE})
  list(APPEND ADDITIONAL_DEFINITIONS -DPICORB_TASK_STACK_SIZE=$ENV{PICORB_TASK_STACK_SIZE})
endif()

set(PICORUBY_DIR ${COMPONENT_DIR}/picoruby)
set(LIBMRUBY_FILE ${PICORUBY_DIR}/build/${LIBMRUBY_PATH}/lib/libmruby.a)

# Expose sdkconfig values to build config via env vars
set(MRUBY_ENV
  MRUBY_CONFIG=${MRUBY_CONFIG_STRING}
  CONFIG_IDF_TARGET=${CONFIG_IDF_TARGET}
)
if(MRUBY_USE_WIFI)
  list(APPEND MRUBY_ENV USE_WIFI=${MRUBY_USE_WIFI})
endif()

# Pick up the port sources of the gems the build config enables.
# The gem list (dependencies included) comes from the build config itself,
# so a gem added to or removed from build_config/*.rb needs no change here.
# Skipped in the early expansion pass, which only collects REQUIRES.
set(PORT_SRCS "")
if(NOT CMAKE_BUILD_EARLY_EXPANSION)
  set(GEM_DIRS_FILE ${CMAKE_BINARY_DIR}/picoruby_gem_dirs.txt)
  execute_process(
    COMMAND ${CMAKE_COMMAND} -E env ${MRUBY_ENV}
      GEM_DIRS_TARGET=${LIBMRUBY_PATH} GEM_DIRS_OUT=${GEM_DIRS_FILE}
      rake --rakelibdir ${COMPONENT_DIR}/rakelib gem_dirs
    WORKING_DIRECTORY ${PICORUBY_DIR}
    RESULT_VARIABLE GEM_DIRS_RESULT
    OUTPUT_VARIABLE GEM_DIRS_LOG
    ERROR_VARIABLE GEM_DIRS_LOG
  )
  if(NOT GEM_DIRS_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to list the mrbgems of ${MRUBY_CONFIG_STRING}:\n${GEM_DIRS_LOG}")
  endif()
  file(STRINGS ${GEM_DIRS_FILE} GEM_DIRS)
  foreach(gem_dir ${GEM_DIRS})
    file(GLOB gem_port_srcs CONFIGURE_DEPENDS
      ${gem_dir}/ports/esp32/*.c
      ${gem_dir}/ports/common/*.c
    )
    list(APPEND PORT_SRCS ${gem_port_srcs})
  endforeach()
  # Reconfigure when the gem list may have changed.
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${MRUBY_CONFIG_STRING})
endif()

idf_component_register(
  SRCS
    ${COMPONENT_DIR}/picoruby-esp32.c
    # Not under ports/esp32/, so PORT_SRCS does not pick it up
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-esp32/ports/esp32.c
    ${PORT_SRCS}
  INCLUDE_DIRS
    ${COMPONENT_DIR}
    ${COMPONENT_DIR}/picoruby/include
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mrubyc/lib/mrubyc/src
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-machine/include
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/include
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/lib/mbedtls/include
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-littlefs/ports/esp32
    ${COMPONENT_DIR}/picoruby/mrbgems/mruby-compiler/include
    ${COMPONENT_DIR}/picoruby/mrbgems/mruby-compiler/lib/prism/include
    ${COMPONENT_DIR}/picoruby/build/prism/include
    ${ADDITIONAL_INCLUDE_DIRS}
  PRIV_REQUIRES
    esp_driver_gpio
    esp_driver_uart
    esp_driver_spi
    esp_driver_ledc
    esp_driver_rmt
    esp_driver_pcnt
    esp_driver_i2c
    esp_adc
    esp_timer
    esp_hw_support
    spi_flash
    nvs_flash
    esp_psram
    esp_driver_usb_serial_jtag
)

add_definitions(
  ${ADDITIONAL_DEFINITIONS}
  -DMRBC_CONVERT_CRLF=1
  -DUSE_FAT_FLASH_DISK
  -DPICORB_PLATFORM_ESP32
  -DNDEBUG
)

# Rebuild libmruby.a when the build config or a custom mrbgem (mrbgems/ at the project root) changes.
# Without DEPENDS this command only runs while libmruby.a does not exist yet.
get_filename_component(CUSTOM_MRBGEMS_DIR ${COMPONENT_DIR}/../../mrbgems ABSOLUTE)
file(GLOB_RECURSE CUSTOM_MRBGEM_FILES CONFIGURE_DEPENDS ${CUSTOM_MRBGEMS_DIR}/*)

# Build PicoRuby
add_custom_command(
  OUTPUT ${LIBMRUBY_FILE}
  COMMAND ${CMAKE_COMMAND} -E echo ${MRUBY_ENV} rake
  COMMAND ${CMAKE_COMMAND} -E env ${MRUBY_ENV} rake
  DEPENDS ${MRUBY_CONFIG_STRING} ${CUSTOM_MRBGEM_FILES}
  WORKING_DIRECTORY ${PICORUBY_DIR}
  COMMENT "PicoRuby build"
  VERBATIM
)

add_prebuilt_library(
  libmruby ${LIBMRUBY_FILE}
  REQUIRES ${COMPONENT_NAME}
)
target_link_libraries(${COMPONENT_LIB} PRIVATE libmruby)
if(CONFIG_ESP_WIFI_ENABLED AND DEFINED ENV{USE_WIFI})
  target_link_libraries(${COMPONENT_LIB} PRIVATE idf::esp_wifi)
endif()
target_include_directories(
  ${COMPONENT_LIB}
  PRIVATE
    ${COMPONENT_DIR}/picoruby/mrbgems/mruby-compiler/include
    ${COMPONENT_DIR}/picoruby/mrbgems/mruby-compiler/lib/prism/include
    ${COMPONENT_DIR}/picoruby/build/prism/include
    ${ADDITIONAL_INCLUDE_DIRS}
)

add_custom_target(
  ${CUSTOM_TARGET_NAME} DEPENDS ${LIBMRUBY_FILE}
)
add_dependencies(${COMPONENT_LIB} ${CUSTOM_TARGET_NAME})

# Compile Ruby files
set(RUBY_FILES main_task)
set(PICORBC ${COMPONENT_DIR}/picoruby/bin/mrbc)
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
