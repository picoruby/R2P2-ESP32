# R2P2-ESP32: PicoRuby/mruby/c 統合ビルドと起動シーケンス詳細設計書

**作成日**: 2025-12-06
**対象**: R2P2-ESP32 プロジェクト全体
**ターゲット**: ESP32 マイクロコントローラー
**ランタイム**: mruby/c VM 上で稼働する PicoRuby

---

## 目次

1. [サブモジュール・ネスト構造](#1-サブモジュールネスト構造の全体像)
2. [rake build パイプライン](#2-rake-build-パイプラインの詳細解説)
3. [rake flash → monitor フロー](#3-rake-flash--monitor-フロー)
4. [ESP32 ブート～REPLプロンプト表示までの詳細フロー](#4-esp32-ブートreplプロンプト表示までの詳細フロー)
5. [キーポイント・まとめ](#5-キーポイントまとめ)
6. [実装参照](#6-実装参照)

---

## 1. サブモジュール・ネスト構造の全体像

### 1.1 ディレクトリ階層

```
R2P2-ESP32 (root)
    ↓
components/picoruby-esp32/  ← submodule (1層目)
    ↓
picoruby/                   ← submodule (2層目)
    ├── mrbgems/
    │   ├── picoruby-mruby/lib/mruby/        ← submodule (3層目)
    │   ├── picoruby-mrubyc/lib/mrubyc/      ← submodule (3層目)
    │   ├── mruby-compiler2/
    │   │   └── lib/prism/                    ← submodule (3層目)
    │   └── picoruby-mruby/lib/estalloc/     ← submodule (3層目)
    │
    ├── build_config/
    │   └── xtensa-esp.rb     ← ESP32 ターゲット設定
    │
    └── lib/                  ← mRuby/c の標準ライブラリ
```

### 1.2 各層の役割

| 層 | パス | 説明 | 役割 |
|---|---|---|---|
| **1層目** | R2P2-ESP32 | ESP32用統合ビルドプロジェクト | Rake定義、CI/CD、全体統合 |
| **2層目** | picoruby-esp32 | PicoRubyのESP32ポート | C/Ruby統合、ESP32固有実装 |
| **3層目** | picoruby | PicoRuby本体 | 複数VMとgem統合、ビルドシステム |
| **4層目** | mrubyc | mRuby/c軽量VM | デバイス最適化VM実装 |
| **4層目** | mruby | mRuby フルVM | 代替VM実装（通常未使用） |
| **4層目** | prism | Ruby 3.3 パーサー | 新型パーサー実装 |

---

## 2. rake build パイプラインの詳細解説

### 2.1 Rakefileの全体構造

**ファイル**: `/home/user/R2P2-ESP32/Rakefile`（77行）

```ruby
# パス定義
R2P2_ESP32_ROOT = File.dirname(File.expand_path(__FILE__))
MRUBY_ROOT = File.join(R2P2_ESP32_ROOT, "components/picoruby-esp32/picoruby")

# mRuby ビルドシステムの読み込み
require "mruby/core_ext"      # mRuby 基本機能
require "mruby/build"         # ビルド設定
require "picoruby/build"      # PicoRuby 拡張機能

# 設定ファイルの読み込み
MRUBY_CONFIG = MRuby::Build.mruby_config_path
load MRUBY_CONFIG
```

### 2.2 メインタスク定義

```ruby
task :default => :all
task :all => %w[build flash monitor]

task :build do
  sh "idf.py build"
end

task :flash do
  sh "idf.py flash"
end

task :monitor do
  sh "idf.py monitor"
end

task :clean do
  sh "idf.py clean"
  FileUtils.cd MRUBY_ROOT do
    %w[xtensa-esp riscv-esp].each do |mruby_config|
      sh "MRUBY_CONFIG=#{mruby_config} rake clean"
    end
  end
end

task :deep_clean => %w[clean] do
  sh "idf.py fullclean"
  rm_rf File.join(MRUBY_ROOT, "build/repos/esp32")
end
```

### 2.3 rake build の実行フロー

```
$ rake build
    ↓
task :all => [build, flash, monitor]
    ↓
task :build => idf.py build
```

### 2.4 idf.py build の内部処理フロー

#### 【ステップ 1】PicoRuby ライブラリのビルド

**CMakeLists.txt の custom command:**

```cmake
# components/picoruby-esp32/CMakeLists.txt (72-79行)
add_custom_command(
  OUTPUT ${LIBMRUBY_FILE}
  COMMAND ${CMAKE_COMMAND} -E echo "MRUBY_CONFIG=${IDF_TARGET_ARCH}-esp rake"
  COMMAND ${CMAKE_COMMAND} -E env MRUBY_CONFIG=${IDF_TARGET_ARCH}-esp rake
  WORKING_DIRECTORY ${PICORUBY_DIR}
  COMMENT "PicoRuby build"
  VERBATIM
)
```

**処理内容:**

1. **環境変数設定**: `MRUBY_CONFIG=xtensa-esp`
   - ESP32 Xtensa ISA ターゲット
   - またはRISC-V ターゲット (ESP32-C3, ESP32-C6)

2. **ビルド設定ファイル**: `build_config/xtensa-esp.rb`

```ruby
MRuby::CrossBuild.new("esp32") do |conf|
  # コンパイラ設定
  conf.toolchain("gcc")
  conf.cc.command = "xtensa-esp32-elf-gcc"    # ESP32用GCC
  conf.linker.command = "xtensa-esp32-elf-ld"
  conf.archiver.command = "xtensa-esp32-elf-ar"

  # mRuby/c VM コンパイル定義
  conf.cc.defines << "MRBC_TICK_UNIT=10"              # 10ms タイムスライス
  conf.cc.defines << "MRBC_TIMESLICE_TICK_COUNT=1"    # 1 tick = 10ms
  conf.cc.defines << "MRBC_USE_FLOAT=2"               # 浮動小数点有効
  conf.cc.defines << "MRBC_CONVERT_CRLF=1"            # UART用 LF→CRLF
  conf.cc.defines << "USE_FAT_FLASH_DISK"             # FAT32FS使用
  conf.cc.defines << "ESP32_PLATFORM"                 # ESP32 プラットフォーム
  conf.cc.defines << "NDEBUG"                         # リリースビルド

  # PicoRuby gembox の有効化
  conf.gembox 'minimum'   # 最小限の標準ライブラリ
  conf.gembox 'core'      # コア機能
  conf.gembox 'shell'     # REPL シェル機能

  # ハードウェア周辺機器 gems
  conf.gem core: 'picoruby-gpio'        # GPIO制御
  conf.gem core: 'picoruby-i2c'         # I2C通信
  conf.gem core: 'picoruby-spi'         # SPI通信
  conf.gem core: 'picoruby-adc'         # ADC（アナログ入力）
  conf.gem core: 'picoruby-uart'        # UART シリアル
  conf.gem core: 'picoruby-pwm'         # PWM制御
  conf.gem core: 'picoruby-esp32'       # ESP32固有API
  conf.gem core: 'picoruby-rmt'         # RMT（LED制御）
  conf.gem core: 'picoruby-mbedtls'     # 暗号化/TLS
  conf.gem core: 'picoruby-adafruit_sk6812'  # SK6812 LED

  # オプション gems
  conf.gem core: 'picoruby-rng'         # 乱数生成
  conf.gem core: 'picoruby-base64'      # Base64
  conf.gem core: 'picoruby-yaml'        # YAML
end
```

3. **Rake実行**: `rake` コマンドで各 gem をコンパイル

#### 【ステップ 2】各 gem の mRuby/c バイトコード化

```
Ruby source files (.rb)
    ↓ picorbc (PicoRuby Compiler)
    ↓
mRuby/c バイトコード (.mrb)
    ↓
linker で libmruby.a に統合
```

**コンパイルされる gems の構成:**

```
picoruby/mrbgems/
├── picoruby-require/          → require() システム
├── picoruby-shell/
│   └── mrblib/shell.rb        → 30行のシェル実装
├── picoruby-io-console/       → STDIN/STDOUT/STDERR
├── picoruby-filesystem-fat/   → FAT32 操作
├── picoruby-machine/          → マシン制御（LED, reset等）
├── picoruby-gpio/             → GPIO制御
├── picoruby-uart/             → UART通信
├── picoruby-i2c/              → I2C通信
├── picoruby-spi/              → SPI通信
├── picoruby-adc/              → ADC入力
├── picoruby-pwm/              → PWM出力
├── picoruby-rmt/              → RMT制御
├── picoruby-watchdog/         → ウォッチドッグタイマー
├── picoruby-env/              → 環境変数
├── picoruby-mbedtls/          → 暗号化
└── ... (30+ gems)
```

#### 【ステップ 3】main_task.rb のコンパイル

**ファイル**: `components/picoruby-esp32/mrblib/main_task.rb`

```cmake
# CMakeLists.txt (105-118行)
foreach(rb main_task)
  set(C_FILE ${COMPONENT_DIR}/mrb/${rb}.c)
  set(RB_FILE ${COMPONENT_DIR}/mrblib/${rb}.rb)
  add_custom_command(
    OUTPUT ${C_FILE}
    COMMAND ${CMAKE_COMMAND} -E echo "Compiling ${RB_FILE}..."
    COMMAND ${CMAKE_COMMAND} -E make_directory ${COMPONENT_DIR}/mrb
    COMMAND ${PICORBC} -B${rb} -o${C_FILE} ${RB_FILE}
    DEPENDS picoruby ${RB_FILE}
    COMMENT "Compiling ${RB_FILE}"
    VERBATIM
  )
  list(APPEND GENERATED_C_FILES ${C_FILE})
endforeach(rb)
```

**処理:**
- `mrblib/main_task.rb` を `picorbc` コンパイラで C言語に変換
- 結果を `mrb/main_task.c` として出力
- これがESP32ファームウェアに組み込まれる

#### 【ステップ 4】ESP32 ファームウェアのリンク

**登録されるソースファイル:**

```cmake
idf_component_register(
  SRCS
    ${COMPONENT_DIR}/picoruby-esp32.c              # メイン初期化
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-esp32/ports/esp32/esp32.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-machine/ports/esp32/machine.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-io-console/ports/esp32/io-console.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-filesystem-fat/ports/esp32/flash_disk.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-gpio/ports/esp32/gpio.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-adc/ports/esp32/adc.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-spi/ports/esp32/spi.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-rng/ports/esp32/rng.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-pwm/ports/esp32/pwm.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-rmt/ports/esp32/rmt.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-watchdog/ports/esp32/watchdog.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-mbedtls/ports/esp32/timing_alt.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-i2c/ports/esp32/i2c.c
    ${COMPONENT_DIR}/picoruby/mrbgems/picoruby-uart/ports/esp32/uart.c
    # ... + C実装ファイル
)
```

#### 【ステップ 5】ビルド出力物

```
build/
├── bootloader.bin               # ブートローダー (0x1000)
├── partition-table.bin          # パーティションテーブル (0x8000)
├── R2P2-ESP32.bin              # ファームウェア (0x10000, factory)
├── R2P2-ESP32.elf              # ELFファイル（デバッグ用）
└── storage.bin                  # FAT32 イメージ (0x210000, storage)
```

### 2.5 ビルドチェーン全体図

```
Rakefile (Ruby)
    ↓
mruby/build (Ruby)
    ↓ MRUBY_CONFIG=xtensa-esp
build_config/xtensa-esp.rb (Ruby)
    ↓
各 mrbgem のビルド
    ├─ .rb ファイル → picorbc → .mrb → C
    ├─ .c ファイル → xtensa-esp32-elf-gcc → .o
    └─ .h ファイル
        ↓
libmruby.a (mRuby/c スタティックライブラリ)
    ↓
main_task.rb → picorbc → main_task.c → .o
    ↓
ESP32 component files (.c)
    ↓
xtensa-esp32-elf-ld (リンカ)
    ↓
R2P2-ESP32.bin (1.5～2.0 MB)
```

---

## 3. rake flash → monitor フロー

### 3.1 フラッシュパーティション設計

**ファイル**: `partitions.csv`

```
Name,       Type,   SubType,  Offset,   Size,    Flags
nvs,        data,   nvs,      0x9000,   0x6000,
phy_init,   data,   phy,      0xf000,   0x1000,
factory,    app,    factory,  0x10000,  2M,
storage,    data,   fat,      ,         1M,
```

### 3.2 フラッシュメモリレイアウト（ESP32: 4MB）

```
0x000000 ┌──────────────────────────┐
         │  ROM Bootloader (内蔵)   │  64KB (固定)
0x008000 ├──────────────────────────┤
         │  ESP-IDF Bootloader      │  16KB
0x009000 ├──────────────────────────┤
         │  NVS (Non-Vol Storage)   │  24KB  (Wi-Fi/BLE設定)
         │  Factory OTA Data        │
0x00f000 ├──────────────────────────┤
         │  PHY Init Data           │  4KB   (RF初期化)
0x010000 ├──────────────────────────┤
         │                          │
         │  Factory Firmware        │  2MB
         │  (mRuby/c VM + gems)     │  (picoruby-esp32.bin)
         │  - bootloader            │
         │  - mRubyc VM             │
         │  - PicoRuby gems         │
         │  - main_task.c           │
         │                          │
0x210000 ├──────────────────────────┤
         │                          │
         │  FAT32 Storage           │  1MB
         │  (/home/app.mrb)         │
         │  (/home/app.rb)          │
         │  (/home/)                │
         │                          │
0x300000 └──────────────────────────┘  4MB上限
```

### 3.3 rake flash の実行処理

```bash
$ rake flash
    ↓
task :flash do
  sh "idf.py flash"
end
```

**idf.py flash が実行する処理:**

1. **シリアルポート自動検出**: `/dev/ttyUSB0` または `/dev/ttyACM0`
2. **ボーレート設定**: 460800 bps（高速フラッシュ）
3. **バイナリの連続書き込み**: esptool.py 呼び出し

**実際の esptool.py コマンド:**

```bash
esptool.py -b 460800 \
  --after default_reset \
  write_flash \
    0x1000 bootloader.bin \
    0x8000 partition-table.bin \
    0x10000 R2P2-ESP32.bin \
    0x210000 storage.bin
```

**所要時間:**
- bootloader + partition: 1秒
- factory firmware (2MB): 5秒
- storage (1MB): 2秒
- 合計: 約10秒

### 3.4 rake monitor フロー

```bash
$ rake monitor
    ↓
task :monitor do
  sh "idf.py monitor"
end
```

**idf.py monitor が行う処理:**

1. **シリアル接続開始**: 115200 baud での UART 通信
2. **ボーレート自動検出**: ESP32からの初期シーケンス検出
3. **出力リアルタイム表示**: ESP32からの UART 出力をターミナルに表示
4. **Ctrl+C で終了**: シリアルモニタ接続解除

---

## 4. ESP32 ブート～REPLプロンプト表示までの詳細フロー

### 4.1 ハードウェアレベルの起動シーケンス

```
┌──────────────────────────────────┐
│ ESP32 ハードウェアリセット        │ (電源投入 or RESET PIN)
└────────────┬─────────────────────┘
             ↓
┌──────────────────────────────────┐
│ 1. ROM ブートローダー (内蔵)      │
│    - クロック初期化               │
│    - RAM 初期化                   │
│    - フラッシュからコード読み込み  │
└────────────┬─────────────────────┘
             ↓
┌──────────────────────────────────┐
│ 2. ESP-IDF ブートローダー        │
│    (0x1000)                       │
│    - SPI フラッシュ初期化         │
│    - パーティション読み込み       │
│    - ファームウェアをRAMにロード   │
└────────────┬─────────────────────┘
             ↓
┌──────────────────────────────────┐
│ 3. ESP-IDF メインプログラム開始   │
│    - FreeRTOS カーネル起動        │
│    - GPIO/UART初期化              │
│    - コンポーネント初期化         │
└────────────┬─────────────────────┘
             ↓
┌──────────────────────────────────┐
│ app_main() 関数呼び出し           │
│ (main/main.c より)                │
└────────────┬─────────────────────┘
             ↓
    実装コード開始 (picoruby_esp32)
```

### 4.2 app_main() エントリーポイント

**ファイル**: `main/main.c`

```c
#include "picoruby-esp32.h"

void app_main(void)
{
  picoruby_esp32();  // PicoRuby初期化＆メインループ
}
```

### 4.3 picoruby_esp32() 関数の詳細実装

**ファイル**: `components/picoruby-esp32/picoruby-esp32.c`

```c
#include <inttypes.h>
#include <nvs_flash.h>
#include "picoruby.h"
#include <mrubyc.h>
#include "mrb/main_task.c"  // コンパイル済みRubyコード

#ifndef HEAP_SIZE
#define HEAP_SIZE (1024 * 120)  // 120KB メモリプール
#endif

static uint8_t heap_pool[HEAP_SIZE];

void initialize_nvs(void)
{
  // Non-Volatile Storage の初期化
  // Wi-Fi設定やBLE設定を保存するNVS領域を初期化
  esp_err_t ret = nvs_flash_init();
  if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
      ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_ERROR_CHECK(nvs_flash_erase());
    ret = nvs_flash_init();
  }
  ESP_ERROR_CHECK(ret);
}

void picoruby_esp32(void)
{
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // ステップ 1: NVS 初期化
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  initialize_nvs();

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // ステップ 2: mRuby/c VM のメモリプール初期化
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  mrbc_init(heap_pool, HEAP_SIZE);
  // → heap_pool[120KB] が mRuby/c のメモリプールになる

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // ステップ 3: メインタスク（Ruby スクリプト）の作成
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  mrbc_tcb *main_tcb = mrbc_create_task(main_task, 0);
  // → main_task = コンパイル済み Ruby bytecode
  //   (main_task.rb が picorbc で変換したもの)

  mrbc_set_task_name(main_tcb, "main_task");
  mrbc_vm *vm = &main_tcb->vm;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // ステップ 4: require システムの初期化（gem loading）
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  picoruby_init_require(vm);
  // → require() メソッドを定義
  // → "require" gem と "io" gem を自動ロード

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // ステップ 5: VM 実行ループ開始（メインループ）
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  mrbc_run();  // ← ここで永遠ループに入る
  // このあと、制御はmRuby/cスケジューラーに移行
  // main_task が実行される
}
```

### 4.4 メモリレイアウト

```
ESP32 RAM (512KB)
┌────────────────────────────┐
│ FreeRTOS Kernel            │  ~100KB
├────────────────────────────┤
│ FreeRTOS Task Stacks       │  ~200KB
├────────────────────────────┤
│ mRuby/c Heap Pool          │  120KB
│ (heap_pool[120KB])         │
│ - Objects, Strings, Arrays │
├────────────────────────────┤
│ その他（グローバル変数等） │
└────────────────────────────┘
```

### 4.5 mrbc_run() の内部動作

mRuby/c のメインループ：

```c
void mrbc_run(void)
{
  while (1) {
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 各タスクをタイムスライス実行
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    for (each task) {
      task->execute_timeslice();  // 10ms 実行
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // タスク状態チェック
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    if (all_tasks_finished()) {
      break;  // 全タスク終了
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // ガベージコレクション
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    mrbc_garbage_collection();

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // スケジュール再編
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  }
}
```

**タイムスライス設定（CMakeLists.txt）:**

```cmake
add_definitions(
  -DMRBC_TICK_UNIT=10                  # 1 tick = 10ms
  -DMRBC_TIMESLICE_TICK_COUNT=1        # 各タスク = 1 tick (10ms)
)
```

### 4.6 main_task.rb の実行シーケンス

**ファイル**: `components/picoruby-esp32/mrblib/main_task.rb`

このRubyスクリプトは、ビルド時に `picorbc` により C に変換されて、ファームウェアに組み込まれます。

```ruby
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# フェーズ 1: 初期化フェーズ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 必須ライブラリ読み込み
require 'machine'      # マシン制御（LED, reset等）
require "watchdog"     # ウォッチドッグタイマー
Watchdog.disable       # ブートシーケンス中に無効化

require "shell"        # シェル実装（REPL）
STDIN = IO.new         # 標準入力初期化
STDOUT = IO.new        # 標準出力初期化

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# フェーズ 2: FAT32 ファイルシステム初期化
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

begin
  # UART エコー無効化
  STDIN.echo = false

  puts "Initializing FLASH disk as the root volume... "

  # flash パーティション (0x210000〜0x300000) をマウント
  Shell.setup_root_volume(:flash, label: 'storage')
  # → FAT::new(:flash) で FAT32 初期化
  # → VFS.mount(fat, "/") で / にマウント

  # システムファイルの整合性チェック・作成
  Shell.setup_system_files

  puts "Available"
rescue => e
  puts "Not available"
  puts "#{e.message} (#{e.class})"
end

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# フェーズ 3: ユーザーアプリケーション実行
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

begin
  # /home/app.mrb または /home/app.rb があれば自動実行
  if File.exist?("/home/app.mrb")
    puts "Loading app.mrb"
    load "/home/app.mrb"
  elsif File.exist?("/home/app.rb")
    puts "Loading app.rb"
    load "/home/app.rb"
  end

  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # フェーズ 4: インタラクティブシェル起動
  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  # Shell オブジェクト生成
  $shell = Shell.new(clean: true)
  puts "Starting shell...\n\n"

  # ロゴ表示
  $shell.show_logo

  # ← ← ← ここから REPL プロンプト が見える！！！
  $shell.start  # ← ユーザーコマンド待機開始

rescue => e
  puts "#{e.message} (#{e.class})"
end
```

### 4.7 Shell.start の処理詳細

**ファイル**: `picoruby/mrbgems/picoruby-shell/mrblib/shell.rb`

```ruby
def start
  loop do
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # プロンプト表示
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    print self.prompt  # "ruby> " または "irb> "

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # ユーザー入力受け取り
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    input = STDIN.gets.chomp  # UART から1行受け取り

    # 空行スキップ
    next if input.empty?

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Ruby コード補記（eval）→ 実行
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    eval(input)

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 結果表示（eval の戻り値）
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # p eval の結果
  end
rescue Interrupt
  puts "\n"
rescue SystemExit
  puts "Bye!"
end
```

### 4.8 実際のシリアル出力例

```
I (28) boot: ESP-IDF v5.4.1 2nd stage bootloader
I (28) boot: compile time Oct 10 2024
I (28) boot: chip revision v1.0
I (32) boot: efuse block revision: 2
...
I (196) app_start: Starting scheduler on CPU0
I (201) app_start: Starting scheduler on CPU1

Initializing FLASH disk as the root volume...
Available

Starting shell...


 .--------.----.----..--..------..----.------.------.
| `--. |  |  | |  ||  |  |____  |  |  |
|  |  | '---' | '  '--'   |     |  |  |
 `------'  `----'  `--' `------'`----'`------'

ruby> ← ← ← REPL PROMPT (ユーザー入力待機！)
```

### 4.9 ユーザーコマンド実行例

```
ruby> puts "Hello from ESP32!"
Hello from ESP32!
=> nil

ruby> 1 + 1
=> 2

ruby> GPIO.digitalWrite(4, 1)
=> 1

ruby> class MyApp
 >   def hello
 >     puts "My app is running!"
 >   end
 > end
=> :hello

ruby> MyApp.new.hello
My app is running!
=> nil

ruby>
```

### 4.10 完全なブートシーケンスタイムライン

| 時刻 | イベント | 処理内容 |
|-----|---------|--------|
| **0ms** | [リセット] | ハードウェアリセット or 電源投入 |
| **10ms** | ROM Bootloader | クロック初期化・RAM初期化 |
| **50ms** | ESP-IDF Bootloader | SPI Flash 初期化・パーティション読み込み |
| **100ms** | ファームウェアロード | factory partition から RAM へロード |
| **150ms** | FreeRTOS 起動 | カーネル開始・CPU0/1 スケジューラー開始 |
| **160ms** | app_main() | picoruby_esp32() 呼び出し |
| **165ms** | NVS 初期化 | nvs_flash_init() |
| **170ms** | mRuby/c 初期化 | mrbc_init(heap_pool, 120KB) |
| **175ms** | main_task 作成 | mrbc_create_task(main_task) |
| **180ms** | mrbc_run() 開始 | VM スケジューラー メインループ開始 |
| **185ms** | main_task.rb 実行 | require 'machine', require 'shell' |
| **250ms** | FAT32 初期化 | Shell.setup_root_volume(:flash) |
| **300ms** | ユーザーアプリ実行 | /home/app.mrb または /home/app.rb 実行 |
| **320ms** | Shell.start | REPL ロゴ表示・プロンプト出現 ← |
| **325ms** | **READY** | **ruby> ← ユーザー入力待機中** |

---

## 5. キーポイント・まとめ

### 5.1 ネストされたサブモジュールの役割分担

| 層 | パス | 役割 | 言語 |
|---|---|---|---|
| **1層** | R2P2-ESP32 | ビルド統合・CI/CD | Ruby (Rake) |
| **2層** | picoruby-esp32 | ESP32ポート実装 | C + Ruby |
| **3層** | picoruby | PicoRubyエコシステム | Ruby |
| **4層** | mrubyc | 軽量VM（メイン） | C |
| **4層** | mruby | フルVM（オプション） | C |
| **4層** | prism | Ruby パーサー | C |

### 5.2 ビルドチェーン：複数言語の統合

```
┌─────────────────┐
│ Ruby スクリプト │ main_task.rb, shell.rb, ...
└────────┬────────┘
         ↓ picorbc コンパイラ
┌─────────────────┐
│ mRuby/c Bytecode│ .mrb バイナリ
└────────┬────────┘
         ↓ linker (ar コマンド)
┌─────────────────┐
│ Cローダーコード │ main_task.c, ...
└────────┬────────┘
         ↓ xtensa-esp32-elf-gcc
┌─────────────────────┐
│ ネイティブバイナリ   │ .o ファイル
│ (Xtensa ISA)        │
└────────┬────────────┘
         ↓ xtensa-esp32-elf-ld
┌─────────────────────┐
│ ELF & BIN           │ R2P2-ESP32.bin
└────────┬────────────┘
         ↓ esptool.py
┌─────────────────────┐
│ フラッシュメモリ    │ 0x10000 (factory)
└─────────────────────┘
```

### 5.3 起動フロー：3つのフェーズ

| # | フェーズ | 所要時間 | 処理 |
|---|---------|--------|------|
| **1** | Hardware Boot | 150ms | ブートローダー・FreeRTOS初期化 |
| **2** | mRuby/c Init | 25ms | VM起動・main_taskビルド・require 初期化 |
| **3** | App Startup | 150ms | FAT32マウント・app.mrb/rb実行・Shell起動 |
| **合計** | **Ready for REPL** | **~320ms** | **ruby> プロンプト出現** |

### 5.4 メモリ配置の最適化

```
ESP32 フラッシュ (4MB)          ESP32 RAM (512KB)
┌──────────────┐                ┌──────────────┐
│ Bootloader   │  16KB           │ FreeRTOS     │  100KB
├──────────────┤                ├──────────────┤
│ NVS          │  24KB           │ FreeRTOS     │  200KB
│ PHY          │  4KB            │ Stacks       │
├──────────────┤                ├──────────────┤
│ Factory FW   │  2MB            │ mRuby/c      │  120KB
│ (mRubyc VM   │                 │ Heap Pool    │
│  + gems)     │                 │              │
├──────────────┤                └──────────────┘
│ FAT32 Storage│  1MB
│ (/home/...)  │
└──────────────┘
```

### 5.5 3段階のコンパイル

```
段階1: Ruby → mRuby/c Bytecode
  picorbc (Ruby → .mrb)
  → gem集約
  → libmruby.a

段階2: mRuby/c + C → オブジェクトコード
  xtensa-esp32-elf-gcc
  → .c → .o
  → リンク
  → main_task.c (Ruby from bytecode)

段階3: オブジェクト → ネイティブバイナリ
  xtensa-esp32-elf-ld
  → R2P2-ESP32.bin
  → esptool.py
  → フラッシュメモリへ書き込み
```

---

## 6. 実装参照

### 6.1 主要ファイルパス

| ファイル | 行数 | 説明 |
|---------|------|------|
| `Rakefile` | 77 | メインビルドタスク定義 |
| `CMakeLists.txt` | - | ルート CMake 設定 |
| `components/picoruby-esp32/CMakeLists.txt` | 121 | PicoRuby コンポーネント設定 |
| `components/picoruby-esp32/picoruby-esp32.c` | 37 | picoruby_esp32() 実装 |
| `main/main.c` | 7 | app_main() エントリーポイント |
| `components/picoruby-esp32/mrblib/main_task.rb` | 37 | 起動スクリプト |
| `picoruby/build_config/xtensa-esp.rb` | 46 | ESP32 ビルド設定 |
| `picoruby/mrbgems/picoruby-shell/mrblib/shell.rb` | 多数 | REPL 実装 |
| `partitions.csv` | - | フラッシュパーティション定義 |
| `.gitmodules` | - | サブモジュール定義 |

### 6.2 ビルド環境変数

```ruby
MRUBY_CONFIG=xtensa-esp  # ESP32 Xtensa 用
MRUBY_CONFIG=riscv-esp   # ESP32-C3/C6 RISC-V 用

IDF_TARGET=esp32         # ESP-IDF ターゲット
IDF_TARGET=esp32c3       # 等々
IDF_TARGET=esp32c6
IDF_TARGET=esp32s3

HEAP_SIZE=120*1024       # mRuby/c メモリ (120KB)
```

### 6.3 定義済みマクロ

```c
MRBC_TICK_UNIT=10              // 1 tick = 10ms
MRBC_TIMESLICE_TICK_COUNT=1    // 各タスク 1 tick
MRBC_USE_FLOAT=2               // 浮動小数点有効
MRBC_CONVERT_CRLF=1            // UART用 LF→CRLF
USE_FAT_FLASH_DISK             // FAT32 使用
ESP32_PLATFORM                 // ESP32 プラットフォーム
NDEBUG                         // リリースビルド
PICORB_VM_MRUBYC              // mRuby/c VM 使用
```

---

## 7. トラブルシューティング

### 7.1 ビルド失敗時

```bash
# キャッシュをクリア
$ rake deep_clean

# 再度ビルド
$ rake build
```

### 7.2 フラッシュ失敗時

```bash
# ターゲットの再設定
$ rake setup_esp32  # または setup_esp32c3, etc.

# 再度フラッシュ
$ rake flash
```

### 7.3 シリアル接続できない時

```bash
# ポート確認
$ ls -la /dev/ttyUSB*  # または /dev/ttyACM*

# idf.py monitor で直接接続テスト
$ idf.py monitor -p /dev/ttyUSB0 -b 115200
```

---

**ドキュメント終了**
