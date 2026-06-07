// components/btstack/btstack_config.h
// Minimal BTstack feature configuration: BLE peripheral + central, FreeRTOS run loop.

#ifndef BTSTACK_CONFIG_H
#define BTSTACK_CONFIG_H

// Port-specific
#define HAVE_FREERTOS_TASK_NOTIFICATIONS
#define HAVE_MALLOC
#define HAVE_ASSERT

// BLE features
#define ENABLE_BLE
#define ENABLE_LE_PERIPHERAL
#define ENABLE_LE_CENTRAL
#define ENABLE_LE_SECURE_CONNECTIONS
#define ENABLE_LE_DATA_LENGTH_EXTENSION
#define ENABLE_L2CAP_LE_CREDIT_BASED_FLOW_CONTROL_MODE
#define ENABLE_GATT_CLIENT_PAIRING
#define ENABLE_PRINTF_HEXDUMP
#define ENABLE_LOG_INFO
#define ENABLE_LOG_ERROR

// Sizes
#define HCI_HOST_ACL_PACKET_NUM     20
#define HCI_HOST_ACL_PACKET_LEN     1024
#define HCI_HOST_SCO_PACKET_NUM     0
#define HCI_HOST_SCO_PACKET_LEN     0
#define HCI_ACL_PAYLOAD_SIZE        (1024+4)
#define HCI_INCOMING_PRE_BUFFER_SIZE 14
#define MAX_NR_HCI_CONNECTIONS      4
#define MAX_NR_GATT_CLIENTS         1
#define MAX_NR_SM_LOOKUP_ENTRIES    3
#define MAX_NR_LE_DEVICE_DB_ENTRIES 4
#define MAX_NR_WHITELIST_ENTRIES    4
#define MAX_ATT_DB_SIZE             512

// le_device_db_tlv.c requires this for non-volatile bonding storage
#define NVM_NUM_DEVICE_DB_ENTRIES   16

// VHCI asynchronous mode (ESP32 port requires this)
#define ENABLE_ESP32_VHCI_ASYNCHRONOUS

// NVS namespace (BTstack uses "BTstack" — no conflict with R2P2 LittleFS)
#define NVS_PARTITION  "nvs"

#endif // BTSTACK_CONFIG_H
