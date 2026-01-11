#include "picoruby-esp32.h"
#include "uart_file_transfer.h"

void app_main(void)
{
  fs_proxy_create_task();
  picoruby_esp32();
}
