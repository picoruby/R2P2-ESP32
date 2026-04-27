#include <inttypes.h>
#include <nvs_flash.h>
#include <esp_heap_caps.h>
#include <esp_psram.h>
#include "picoruby.h"
#include "sdkconfig.h"
#include "driver/uart_vfs.h"
#if defined(CONFIG_ESP_CONSOLE_SECONDARY_USB_SERIAL_JTAG) || \
    defined(CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG)
#include "driver/usb_serial_jtag_vfs.h"
#endif

#if defined(PICORB_VM_MRUBYC)
#include <mrubyc.h>
#elif defined(PICORB_VM_MRUBY)
#include "hal.h" // in picoruby-machine
#endif

#include "mrb/main_task.c"

#ifndef HEAP_SIZE
#if defined(CONFIG_SPIRAM)
#define HEAP_SIZE (1024 * 1024)
#else
#define HEAP_SIZE (1024 * 100)
#endif
#endif

uint8_t *heap_pool = NULL;
uint32_t caps = MALLOC_CAP_INTERNAL;

#if defined(PICORB_VM_MRUBY)
mrb_state *global_mrb = NULL;
#endif

void
setup(void)
{
  /* Disable VFS line ending conversion globally (TX and RX) so that binary
   * data is never mangled. Terminal emulators that require CRLF on TX should
   * handle it on the host side. This matches the RP2040 behaviour. */
  uart_vfs_dev_port_set_tx_line_endings(CONFIG_ESP_CONSOLE_UART_NUM, ESP_LINE_ENDINGS_LF);
  uart_vfs_dev_port_set_rx_line_endings(CONFIG_ESP_CONSOLE_UART_NUM, ESP_LINE_ENDINGS_LF);
#if defined(CONFIG_ESP_CONSOLE_SECONDARY_USB_SERIAL_JTAG) || \
    defined(CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG)
  usb_serial_jtag_vfs_set_tx_line_endings(ESP_LINE_ENDINGS_LF);
  usb_serial_jtag_vfs_set_rx_line_endings(ESP_LINE_ENDINGS_LF);
#endif

  esp_err_t ret = nvs_flash_init();
  if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_ERROR_CHECK(nvs_flash_erase());
    ret = nvs_flash_init();
  }
  ESP_ERROR_CHECK(ret);

#if defined(CONFIG_SPIRAM)
  caps = MALLOC_CAP_SPIRAM;
#endif
  heap_pool = heap_caps_malloc(HEAP_SIZE, caps);
  if (!heap_pool) {
    printf("Failed to allocate heap pool\n");
    return;
  }
}

void
teardown(void)
{
  if (heap_pool) {
    heap_caps_free(heap_pool);
    heap_pool = NULL;
  }

  nvs_flash_deinit();
}

void
picoruby_esp32(void)
{
  setup();

#if defined(PICORB_VM_MRUBYC)
  mrbc_init(heap_pool, HEAP_SIZE);

  mrbc_tcb *main_tcb = mrbc_create_task(main_task, 0);
  mrbc_set_task_name(main_tcb, "main_task");
  mrbc_vm *vm = &main_tcb->vm;

  picoruby_init_require(vm);
  mrbc_run();
#elif defined(PICORB_VM_MRUBY)
  mrb_state *mrb = mrb_open_with_custom_alloc(heap_pool, HEAP_SIZE);
  global_mrb = mrb;
  mrc_irep *irep = mrb_read_irep(mrb, main_task);
  mrc_ccontext *cc = mrc_ccontext_new(mrb);
  mrb_value name = mrb_str_new_lit(mrb, "R2P2");
  mrb_value task = mrc_create_task(cc, irep, name, mrb_nil_value(), mrb_obj_value(mrb->top_self));
  if (mrb_nil_p(task)) {
    const char *msg = "mrbc_create_task failed\n";
    hal_write(1, msg, strlen(msg));
  }
  else {
    mrb_task_run(mrb);
  }
  if (mrb->exc) {
    mrb_print_error(mrb);
  }
  mrb_close(mrb);
  mrc_ccontext_free(cc);
#endif

  teardown();
}
