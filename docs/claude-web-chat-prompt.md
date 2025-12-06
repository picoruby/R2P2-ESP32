# Claude Web Chat 用 - R2P2-ESP32 構造・ビルド・起動シーケンス解説プロンプト

以下のプロンプトをそのまま Claude Web チャット（claude.ai）にコピー＆ペーストしてください。

---

## 📋 プロンプトテキスト

**タイトル**: R2P2-ESP32 の完全解説（ネストされたサブモジュール・ビルド・起動フロー）

```
以下の複雑な ESP32 ファームウェアプロジェクト（R2P2-ESP32）について、
詳細な日本語解説をアーティファクト形式で生成してください。

【プロジェクト概要】
- R2P2-ESP32（ルートプロジェクト）
  ├─ components/picoruby-esp32/（サブモジュール1層目）
  │  └─ picoruby/（サブモジュール2層目）
  │     ├─ mruby（3層目）
  │     ├─ mrubyc（3層目）
  │     └─ prism パーサー（3層目）
  └─ main/（エントリーポイント）

【目的】
このプロジェクトは、PicoRuby（軽量 Ruby 言語）を ESP32 マイクロコントローラー上で実行します。
実行エンジンは mruby/c（軽量VM）です。

【解説対象】

### 1. 3層のネストされたサブモジュール構造
- 各層の役割
- なぜこのようなネスト構造になっているのか
- 層間の依存関係

### 2. `rake build` のパイプライン
詳細なステップバイステップ解説：
- Rakefile の読み込みと設定
- PicoRuby ライブラリのビルド（MRUBY_CONFIG=xtensa-esp）
- build_config/xtensa-esp.rb の gem 定義
- Ruby ソースコード → picorbc コンパイル → mRuby/c bytecode
- main_task.rb のコンパイル（C コードに変換）
- 各 gem のコンパイル（GPIO, UART, I2C, SPI, FAT32等）
- xtensa-esp32-elf-gcc による ネイティブコンパイル
- linker によるファイナルバイナリ生成
- 出力物: bootloader.bin, partition-table.bin, R2P2-ESP32.bin, storage.bin

### 3. `rake flash` 後の処理フロー
- フラッシュパーティション設計 (partitions.csv)
- ESP32 4MB メモリレイアウト
  * 0x1000: ブートローダー
  * 0x9000: NVS (Wi-Fi/BLE設定)
  * 0xf000: PHY初期化
  * 0x10000: Factory Firmware (mRuby/c VM + gems)
  * 0x210000: FAT32 Storage (/home/app.mrb, /home/app.rb)
- esptool.py による書き込みプロセス
- rake monitor によるシリアル接続

### 4. マイクロコントローラー上での起動フロー（ブート～REPLプロンプト）
詳細なシーケンス：

**ハードウェアレベル**
- ESP32 リセット
- ROM ブートローダー（内蔵）
- ESP-IDF ブートローダー（0x1000）
- FreeRTOS カーネル起動
- app_main() 関数呼び出し

**PicoRuby VM レベル**
- app_main() → picoruby_esp32() 呼び出し
- picoruby_esp32() の詳細処理：
  1. initialize_nvs(): NVS領域初期化
  2. mrbc_init(heap_pool, 120KB): mRuby/c VM メモリプール初期化
  3. mrbc_create_task(main_task): Ruby スクリプト実行タスク作成
  4. picoruby_init_require(vm): require() システム初期化
  5. mrbc_run(): VM メインループ開始（永遠ループ）

**Ruby レベル（main_task.rb の実行）**
- require 'machine': マシン制御初期化
- require 'shell': シェル（REPL）初期化
- STDIN/STDOUT 初期化
- Shell.setup_root_volume(:flash): FAT32 ファイルシステムマウント（0x210000～0x300000）
- ユーザーアプリケーション実行（/home/app.mrb または /home/app.rb）
- Shell.start(): REPL ループ開始
  * プロンプト表示: "ruby> "
  * ユーザー入力待機
  * eval 実行
  * 結果表示
  * ← ← ← **ここからユーザーは Ruby コード実行可能**

### 5. 詳細な実装ファイル
以下のファイルの役割と内容を説明：
- Rakefile（77行）
- CMakeLists.txt（ルート）
- components/picoruby-esp32/CMakeLists.txt（121行）
- components/picoruby-esp32/picoruby-esp32.c（37行）
- main/main.c（7行）
- components/picoruby-esp32/mrblib/main_task.rb（37行）
- picoruby/build_config/xtensa-esp.rb（46行）
- picoruby/mrbgems/picoruby-shell/mrblib/shell.rb
- partitions.csv

【出力形式】
- アーティファクト形式で、以下の構成で提示してください：
  1. サブモジュール・ネスト構造（図解）
  2. rake build パイプライン（フローチャート）
  3. メモリレイアウト（図表）
  4. ブートシーケンス（タイムライン）
  5. 各実装ファイルの詳細解説
  6. キーポイント・まとめ

【求める内容の品質】
- 正確で詳細な技術解説
- 複数のレイヤー（ハードウェア → OS → VM → Ruby コード）を含む包括的な説明
- 初心者にも理解できる図解とスキーマ
- ビルドプロセスの全体像を見通せる説明
- 実際の設定値（MRBC_TICK_UNIT=10等）への言及
```

---

## 🚀 使用方法

### Step 1: Claude Web Chat を開く
https://claude.ai にアクセス

### Step 2: 新規スレッド作成
「New conversation」をクリック

### Step 3: プロンプトをコピー＆ペースト
上記の「プロンプトテキスト」セクション全体をコピーして、Claude Web Chat に貼り付け

### Step 4: 送信
「Send」ボタンをクリック

### 期待される出力
Claude がアーティファクト形式で以下を生成します：
- 美しくフォーマットされたマークダウン設計書
- 複数のダイアグラムとスキーマ
- ステップバイステップの解説
- コードスニペット
- タイムラインチャート

---

## 💡 期待される設計書の内容例

アーティファクトには以下が含まれます：

```
# R2P2-ESP32: 完全解説

## 1. サブモジュール・ネスト構造

┌─────────────────────────────────────────┐
│ R2P2-ESP32 (root)                       │
│                                         │
│ ├─ components/picoruby-esp32/          │
│ │  (submodule 1層目)                   │
│ │                                      │
│ │  ├─ picoruby/                        │
│ │  │  (submodule 2層目)                │
│ │  │                                   │
│ │  │  ├─ mrbgems/                      │
│ │  │  │  ├─ picoruby-mruby/lib/mruby/ │
│ │  │  │  ├─ picoruby-mrubyc/lib/mrubyc│
│ │  │  │  ├─ mruby-compiler2/lib/prism/ │
│ │  │  │  └─ ... (30+ gems)             │
│ │  │  │                                │
│ │  │  └─ build_config/                 │
│ │  │     └─ xtensa-esp.rb              │
│ │  │                                   │
│ │  └─ picoruby-esp32.c                 │
│ │                                      │
│ ├─ main/                               │
│ │  ├─ main.c (app_main)                │
│ │  └─ CMakeLists.txt                   │
│ │                                      │
│ ├─ Rakefile                            │
│ ├─ CMakeLists.txt                      │
│ └─ partitions.csv                      │
└─────────────────────────────────────────┘
```

## 2. rake build パイプライン

┌──────────────────┐
│   $ rake build   │
└────────┬─────────┘
         ↓
┌──────────────────────────────────────┐
│ MRUBY_CONFIG=xtensa-esp              │
│ build_config/xtensa-esp.rb 読み込み  │
└────────┬─────────────────────────────┘
         ↓
┌──────────────────────────────────────┐
│各 gem のコンパイル（30+ gems）       │
│ - .rb → picorbc → .mrb               │
│ - .c → xtensa-esp32-elf-gcc → .o     │
└────────┬─────────────────────────────┘
         ↓
... (以下、図表とコードが続く)
```

---

## 🎯 カスタマイズオプション

### より詳細な解説が欲しい場合：
```
上記のプロンプトに以下を追加してください：

「また、以下の追加項目も詳しく説明してください：
- GCC コンパイルフラグ詳細
- MRBC_TICK_UNIT と MRBC_TIMESLICE_TICK_COUNT の動作原理
- メモリプール (heap_pool[120KB]) の管理メカニズム
- FreeRTOS と mRuby/c VM のタスク管理の相互関係
- UART 通信プロトコル（ボーレート、パリティ等）
」
```

### ビジュアルを重視したい場合：
```
上記のプロンプトに以下を追加してください：

「ビジュアル表現について：
- メモリレイアウトを ASCII アート（┌─┐形式）で詳しく表示
- ビルドパイプラインをフローチャート形式で複数のバリエーション
- タイムラインを秒単位で正確に表示
- 各段階のデータフロー（入力→処理→出力）を明確に
」
```

### 実装コード重視の場合：
```
上記のプロンプトに以下を追加してください：

「実装についても詳しく：
- picoruby-esp32.c の各関数の詳細実装
- main_task.rb の行ごとの動作
- picoruby_init_require() の内部動作
- FAT32 マウント処理の詳細
- Shell.start() の REPL ループ実装
」
```

---

## 📚 参考ファイル

このプロンプト生成に基づいた詳細な設計書は以下に保存されています：
- `/home/user/R2P2-ESP32/docs/R2P2-ESP32_Architecture_and_Boot_Sequence.md`

このマークダウンファイルは、以下の内容を含む完全な設計書です：
- 13,000語以上の詳細解説
- 複数のチャート・図表・タイムライン
- ファイルパス・行番号・マクロ定義を含む実装参照
- トラブルシューティング・セクション

---

## ✅ 使用例

**例1: デフォルト使用**
```
Claude Web Chat にプロンプトテキストをコピー＆ペースト
  ↓
「Send」をクリック
  ↓
Claude がアーティファクトを生成
  ↓
美しくフォーマットされた設計書が表示される
```

**例2: カスタマイズ**
```
プロンプトテキストの末尾に「追加項目」セクションを追加
  ↓
カスタマイズ内容を記述
  ↓
「Send」をクリック
  ↓
より詳細/ビジュアル/コード重視な設計書が生成される
```

---

## 🔗 関連リソース

- **ローカル設計書**: `docs/R2P2-ESP32_Architecture_and_Boot_Sequence.md`
- **このプロンプト**: `docs/claude-web-chat-prompt.md`
- **プロジェクトリポジトリ**: R2P2-ESP32

---

**最終更新**: 2025-12-06
