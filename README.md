# WIDE TETRIS

[日本語](#日本語) | [简体中文](#简体中文) | [English](#english)

---

## 日本語

### 概要

WIDE TETRIS は Godot 4 で制作された現代的な Tetris クローンです。SRS 回転、Hold、7-Bag、Lock Delay、B2B、Combo、Garbage Queue、T-Spin 判定、ローカル統計、リプレイ閲覧、AI リプレイ分析を含みます。

現在の AI 分析はプレイ中の支援ではなく、対局後のリプレイ分析用です。プレイヤーは各配置の良し悪し、ミスになった判断、AI が推奨する配置をリプレイ画面で確認できます。

### 実行方法

1. [Godot Engine](https://godotengine.org/download/) 4.x をインストールします。
2. Godot Project Manager で `Import` を選びます。
3. このリポジトリ直下の `project.godot` を選択します。
4. エディタ右上の Play ボタン、または `F5` で起動します。

### リプレイ AI 分析

リプレイ分析は `replay-ai-core` に含まれる Cold Clear 系の評価ロジックを使います。以前の Python/MLP ベースの評価は、リプレイ画面からは使わない方針です。

分析の流れ:

1. プレイヤーがリプレイ画面で session JSON を選択します。
2. 同じフォルダに `session_xxx_analyzed.json` があるか確認します。
3. 既存ファイルが Cold Clear 形式ならそのまま読み込みます。
4. ない場合、または旧 MLP 形式の場合、`analyze_session.exe` を実行して新しく生成します。

出力される主な項目:

- `ai_scores`: 各手の Cold Clear 評価スコア
- `ai_details`: 実際の配置、順位、最善手との差、品質ラベル
- `recommendations`: 各手での上位推奨配置

### ユーザー向け配布

Windows 版の分析ツールは同梱済みです。

```text
replay-ai-core/bin/windows/analyze_session.exe
```

通常ユーザーは Rust をインストールする必要はありません。ゲーム起動時に `ReplayAiEnvironment` が分析ツールを探し、必要なら PCK 内の exe を外部にコピーして使います。

探索順の例:

- ゲーム exe と同じフォルダの `analyze_session.exe`
- `bin/windows/analyze_session.exe`
- `replay-ai-core/bin/windows/analyze_session.exe`
- `user://replay-ai-core/bin/windows/analyze_session.exe`
- エディタ実行時の `res://replay-ai-core/bin/windows/analyze_session.exe`

### Rust 開発者向け

Cold Clear ベースの分析ツールを変更した場合は、Rust toolchain が必要です。

必要なもの:

- Rust stable
- Cargo
- Windows では MSVC toolchain または Rust が要求する C/C++ ビルド環境

ビルド:

```powershell
cd replay-ai-core
cargo check -p replay-analysis
cargo build -p replay-analysis --bin analyze_session --release
```

ビルド後、配布用 exe を更新します。

```powershell
copy target\release\analyze_session.exe bin\windows\analyze_session.exe
```

`replay-ai-core/target/` はビルドキャッシュなので Git に含めません。

### 主なディレクトリ

```text
assets/                 画像などのアセット
audio/                  BGM と効果音
docs/                   設計資料
lang/                   多言語 CSV
scenes/                 Godot シーン
scripts/core/           Board、Piece、GameState、データ保存、AI 環境
scripts/game/           ゲーム進行、スコア、対戦ロジック
scripts/input/          DAS/ARR と入力処理
scripts/ui/             ロビー、設定、リプレイ UI
replay-ai-core/          Cold Clear ベースの Rust リプレイ分析コア
server/                 Node.js サーバー
userdata/               ローカル実行時の保存データ
```

---

## 简体中文

### 项目简介

WIDE TETRIS 是一个使用 Godot 4 开发的现代俄罗斯方块项目。项目包含 SRS 旋转、Hold、7-Bag、锁定延迟、B2B、Combo、垃圾行队列、T-Spin 判定、本地统计、对局回放和 AI 复盘分析。

当前 AI 的目标不是在玩家游玩中实时辅助，而是在对局结束后，通过 replay 分析帮助玩家快速判断每一步操作的好坏，发现导致失误的放置或判断，并看到 AI 推荐的更优落点。

### 运行方法

1. 安装 [Godot Engine](https://godotengine.org/download/) 4.x。
2. 打开 Godot Project Manager，点击 `Import`。
3. 选择本仓库根目录下的 `project.godot`。
4. 点击编辑器右上角的运行按钮，或按 `F5` 启动游戏。

### Replay AI 分析

复盘分析现在使用 `replay-ai-core` 中的 Cold Clear 评价逻辑。旧的 Python/MLP 评价不再作为 replay 界面的主要分析方式。

分析流程:

1. 玩家在 replay 分析界面选择一个 session JSON。
2. 系统检查同目录是否已有 `session_xxx_analyzed.json`。
3. 如果已有文件是 Cold Clear 新格式，直接读取缓存。
4. 如果没有，或者发现是旧 MLP 格式，则调用 `analyze_session.exe` 重新生成。

输出中的主要字段:

- `ai_scores`: 每一步的 Cold Clear 评价分数
- `ai_details`: 实际落点、排名、与最佳落点的差距、质量标签
- `recommendations`: 每一步的上位推荐落点

### 面向普通用户的分发

Windows 版分析工具已经随仓库提供：

```text
replay-ai-core/bin/windows/analyze_session.exe
```

普通玩家不需要安装 Rust，也不需要自己编译。游戏启动时，`ReplayAiEnvironment` 会自动查找分析工具。如果工具被打包在 PCK 里，游戏会把它复制到可执行位置后再调用。

支持的查找位置包括:

- 游戏 exe 同目录下的 `analyze_session.exe`
- `bin/windows/analyze_session.exe`
- `replay-ai-core/bin/windows/analyze_session.exe`
- `user://replay-ai-core/bin/windows/analyze_session.exe`
- 编辑器环境下的 `res://replay-ai-core/bin/windows/analyze_session.exe`

### Rust 开发者编译方法

如果修改了 Cold Clear 相关代码或 replay analyzer，需要安装 Rust toolchain。

需要:

- Rust stable
- Cargo
- Windows 上需要 MSVC toolchain，或 Rust 所要求的 C/C++ 构建环境

编译:

```powershell
cd replay-ai-core
cargo check -p replay-analysis
cargo build -p replay-analysis --bin analyze_session --release
```

编译完成后，更新分发用 exe:

```powershell
copy target\release\analyze_session.exe bin\windows\analyze_session.exe
```

`replay-ai-core/target/` 是 Cargo 构建缓存，不要提交到 Git。

### 主要目录

```text
assets/                 图片等资源
audio/                  BGM 与音效
docs/                   架构和数据文档
lang/                   多语言 CSV
scenes/                 Godot 场景
scripts/core/           Board、Piece、GameState、数据存储、AI 环境
scripts/game/           游戏流程、计分、对战逻辑
scripts/input/          DAS/ARR 与输入处理
scripts/ui/             大厅、设置、复盘 UI
replay-ai-core/          基于 Cold Clear 的 Rust 复盘分析核心
server/                 Node.js 服务端
userdata/               本地运行时保存数据
```

---

## English

### Overview

WIDE TETRIS is a modern Tetris project built with Godot 4. It includes SRS rotation, Hold, 7-Bag, lock delay, B2B, combo, garbage queue, T-Spin detection, local player statistics, replay viewing, and AI replay analysis.

The current AI goal is post-game analysis, not live in-game assistance. After a match, players can review each placement, spot mistakes, and compare their move with AI-recommended placements.

### How to Run

1. Install [Godot Engine](https://godotengine.org/download/) 4.x.
2. Open the Godot Project Manager and click `Import`.
3. Select `project.godot` from the repository root.
4. Click the Play button in the editor, or press `F5`.

### Replay AI Analysis

Replay analysis now uses the Cold Clear based evaluator in `replay-ai-core`. The old Python/MLP evaluator is no longer the main replay analysis path.

Analysis flow:

1. The player selects a session JSON in the replay analysis screen.
2. The game checks for `session_xxx_analyzed.json` in the same folder.
3. If it is already in the new Cold Clear format, the cache is loaded.
4. If it is missing or still in the old MLP format, the game runs `analyze_session.exe` and writes a new analyzed JSON.

Main output fields:

- `ai_scores`: Cold Clear score for each move
- `ai_details`: actual placement, rank, loss against the best move, quality label
- `recommendations`: top recommended placements for each move

### Distribution For Players

The Windows analyzer is included in the repository:

```text
replay-ai-core/bin/windows/analyze_session.exe
```

Players do not need Rust or Cargo. On startup, `ReplayAiEnvironment` prepares the analyzer automatically. If the executable is inside the PCK, the game copies it to an executable location before using it.

Supported lookup locations include:

- `analyze_session.exe` next to the game exe
- `bin/windows/analyze_session.exe`
- `replay-ai-core/bin/windows/analyze_session.exe`
- `user://replay-ai-core/bin/windows/analyze_session.exe`
- `res://replay-ai-core/bin/windows/analyze_session.exe` when running from the editor

### Rust Developer Build

Developers need Rust only when changing the Cold Clear based analyzer.

Requirements:

- Rust stable
- Cargo
- On Windows, the MSVC toolchain or the C/C++ build tools required by Rust

Build:

```powershell
cd replay-ai-core
cargo check -p replay-analysis
cargo build -p replay-analysis --bin analyze_session --release
```

After building, refresh the distributable executable:

```powershell
copy target\release\analyze_session.exe bin\windows\analyze_session.exe
```

Do not commit `replay-ai-core/target/`; it is Cargo build cache.

### Main Directories

```text
assets/                 Image and UI assets
audio/                  Music and sound effects
docs/                   Architecture and data documentation
lang/                   Localization CSV files
scenes/                 Godot scenes
scripts/core/           Board, Piece, GameState, data storage, AI environment
scripts/game/           Game flow, scoring, multiplayer logic
scripts/input/          DAS/ARR and input handling
scripts/ui/             Lobby, settings, replay UI
replay-ai-core/          Rust replay analysis core based on Cold Clear
server/                 Node.js server
userdata/               Local runtime player data
```
