# WIDE TETRIS

[日本語](#日本語) | [简体中文](#简体中文) | [English](#english)

---

## 日本語

### 実行方法 (How to Run)
1.  [Godot Engine](https://godotengine.org/download/) (v4.x) をダウンロードしてインストールします。
2.  Godot Engineプロジェクトマネージャーを開き、`インポート (Import)` をクリックします。
3.  このリポジトリのルートにある `project.godot` ファイルを選択してプロジェクトをインポートします。
4.  エディタ上の再生ボタン（または `F5` キー）を押してゲームを開始します！

### 全体的な実装アーキテクチャ (Overall Implementation)
WIDE TETRISはGodot Engineで構築された、モダンで高度にモジュール化されたテトリスゲームです。主なアーキテクチャの原則は以下の通りです：
*   **分離とモジュール化**: 動的にコードで生成するのではなく、Godotのシーンシステムとプレハブ（`.tscn`）を最大限に活用し、コンポーネントの独立性を保ちます。
*   **データ駆動型**: `@export` を使用して重力や入力（DAS/ARR）などのパラメーターを公開し、インスペクターでの微調整を可能にしています。
*   **グローバル状態管理**: シーン切り替え時の状態（プレイヤー名など）を管理するために、極めて純粋なメモリ上のシングルトン (AutoLoad `GameState`) を採用しています。
*   **ノードベースのUI**: プラグアンドプレイのUIコンポーネント（設定メニューなど）や、ゲームオーバー時のフォーカス管理にネイティブのGodotフォーカスシステムを使用し、コントローラーの完全サポートを実現しています。

### 完全なファイル構造 (File Structure)
プロジェクトは保守性と明瞭さを維持するために整理されています：
```text
whgame_Tetris-godot/
├── assets/                  # アセットファイル（画像、フォントなど）
├── audio/                   # サウンドエフェクトとBGM (.wav, .ogg)
├── docs/                    # ドキュメント（アーキテクチャとゲームデザイン）
├── lang/                    # Godot CSV 多言語対応システム
├── scenes/                  # `.tscn` プレハブとシーンの集約場所
│   ├── ui/                  # ログイン、ロビー、設定メニューなどのUI関連
│   └── game.tscn            # メインのゲームプレイ・ルートシーン
├── scripts/                 # GDScript ソースコード
│   ├── core/                # ブロック、盤面、SRS、シングルトン (GameState)
│   ├── input/               # キーボード/ゲームパッドの入力とDAS/ARR処理
│   ├── game/                # スコア計算、メインゲームループ
│   └── ui/                  # UI制御とマネージャー
└── project.godot            # Godotプロジェクトのメイン設定と入力マップ
```

### コアコードロジック (Core Logic)

#### スーパーローテーションシステム (SRS: Super Rotation System)
I, O, T, S, Z, J, Lの7種のテトリミノに対して、SRS標準の回転アルゴリズムを実装しています。
*   **ウォールキック (Wall Kick)**: ブロックが壁や他のブロックに衝突した際、定義された定数オフセットの表を参照し、回転を成立させます。一般ブロック用と、弾力的な動きをするIブロック用の独立した計算式があり、GodotのY軸下向き2D座標を考慮した設計になっています。

#### モダンテトリスの機能 (Modern Tetris Features)
*   **ロックダウン遅延 (Lock Delay)**: 接地後0.5秒の猶予があり、移動や回転でタイマーがリセットされます。無限遅延を防ぐため、1段につき最大15回の操作制限 (Max Resets) がかけられています。
*   **ホールド (Hold)**: 現在のブロックをストックでき、一度使用すると次のブロックが確定するまで再使用できない仕組みを実装しています。
*   **7種ランダムジェネレーター (7-Bag)**: 7つのブロックを1セットとしてシャッフルし、排出する仕組みです。偏りや特定のブロックが来ない事態を防ぎます。
*   **ゴミブロックシステムとコンボ (Garbage Lines)**: 
    *   消去ライン数、T-Spin、Perfect Clearなどに基づき、相手側に送るゴミの量が変動します。Back-To-Back (B2B) やコンボによるボーナスも実装。
    *   **ゴミキュー (Garbage Queue)**: プレイヤーは警告ゲージを受け取り、自分のブロックが確定するまでにラインを消すことで、せり上がるゴミブロックを相殺（シールド）することが可能です。

---

## 简体中文

### 运行与使用方法
1.  下载并安装 [Godot Engine](https://godotengine.org/download/) (v4.x 版本)。
2.  打开 Godot 引擎项目管理器，点击 `导入 (Import)`。
3.  选择并导航到本仓库根目录下的 `project.godot` 文件进行导入。
4.  在引擎界面中，点击右上角的“运行项目”播放按钮（或按下 `F5` 键）即可开始游戏！

### 整体实现机制
WIDE TETRIS 采用 Godot Engine 构建，遵循现代化与高度模块化的理念。核心架构原则如下：
*   **解耦与静态化优先**：全面拥抱 Godot 的场景系统。尽量将功能封装为预制件 (`.tscn`) 而非代码动态拼装，以降低耦合。
*   **参量导出与数据驱动**：广泛使用 `@export` 将游戏手感参数（重力、DAS/ARR、出生列）暴露至检查器，方便非程序策划直接调试控制。
*   **常驻内存管理**：利用极简的 AutoLoad 单例 (`/root/GameState`) 暂存跨场景变量，避免频繁写入本地配置文件造成 I/O 阻塞流。
*   **彻底剥离的 UI 树**：热插拔式 UI 组件完美解决内存污染，配合原生全环境手柄焦点 (Focus) 引擎，实现无缝菜单转场与死局操作接管。

### 完全的文件结构
工程目录严格区分为以下模块：
```text
whgame_Tetris-godot/
├── assets/                  # 美术资产、字体等资源
├── audio/                   # .wav 短促音效及 .ogg 常驻背景音乐
├── docs/                    # 引擎外部分享文件（开发手记等）
├── lang/                    # Godot CSV 专用多语言包映射表
├── scenes/                  # 游戏切片化节点组装预制件核心区域
│   ├── ui/                  # 大厅、登录、悬浮设置中心窗等组件
│   └── game.tscn            # 顶级马拉松对战场景树结构
├── scripts/                 # 驱动脚本目录
│   ├── core/                # 下落块逻辑、SRS旋转矩阵、全局单例悬挂
│   ├── input/               # 手柄与键盘 DAS/ARR 连发解析控制器
│   ├── game/                # 得分核算与主时钟计时器控制流
│   └── ui/                  # 界面层级流转处理及节点级管理器
└── project.godot            # Godot 引擎总程配置与按键映射地图
```

### 代码核心逻辑与现代特性

#### SRS (超级旋转系统) 的实现
完全遵照 Guidelines 规范开发 7 种方块 (I, O, T, S, Z, J, L) 的四相自转功能与碰撞体系。
*   **踢墙机制 (Wall Kick)**：当方块旋转空间受限时，程序会自动查询静态常量二维阵列。J, L, S, T, Z 块共享一套基于 3×3 中心的推力表；I 方块则拥有独立的、跨度极端的测试补偿阵列。算法原生适配了引擎向下 Y 轴的正相映射，支持最多同时验证 5 个不同的坐标偏移量。

#### 现代俄罗斯方块经典特性
*   **锁定延迟 (Lock Delay)**：方块触底不立即“死亡”，默认给予 0.5 秒缓冲计时层。玩家可平移或旋转以触发“操作重置”，但受制于 15 次同高度防无限拖延机制控制限界。
*   **暂存防误触机制 (Hold)**：允许把现正控制的方块收回 Hold 槽位，内部引入变灰失能逻辑，使得每次落下动作循环中至多只能发生一次替换，并确保被换回的方块状态重置为 0 相位。
*   **7-袋随机器 (7-Bag)**：采用将 7 枚各异方块混组为一“袋”并进行打乱抽发的发牌流派，杜绝伪随机逻辑产生连续的极端坏死块，确保操作流顺滑。
*   **对战环境与垃圾行系统 (Garbage Lines)**：
    *   构建了完备的伤害倍数换算表（涵盖各项 T-Spin、Perfect Clear 以及 Back-to-Back 附魔补偿加成）。
    *   **动态垃圾队列**：当承受敌方突袭火力时存在变色的队列“预警槽防护期”，允许玩家在这关键段借用自身消除火力进行 1 换 1 化解护盾输出，而非直接承受底盘突升惩罚。

---

## English

### How to Run
1.  Download and install [Godot Engine](https://godotengine.org/download/) (v4.x).
2.  Open the Godot Engine Project Manager and click `Import`.
3.  Browse and select the `project.godot` file located in the root of this repository to import the project.
4.  Click the Play button in the top right corner of the editor (or press `F5`) to start the game!

### Overall Implementation Overview
WIDE TETRIS is built on the Godot Engine, designed with modern and modular development practices. The core architectural principles include:
*   **Decoupling & Prefabs First**: Emphasizing Godot's visual scene tree workflow. Dynamic rendering is avoided; instead, UI and logical elements are constructed as pure static `.tscn` prefabs to preserve loose coupling.
*   **Data-Driven Design**: Expansive use of `@export` variables to expose handling tuners (DAS/ARR, gravity rates, board sizing) efficiently into the Godot Inspector for balancing accessibility.
*   **Memory Singleton Pattern**: Uses a lightweight AutoLoad base (`/root/GameState`) to suspend transitive variables safely in memory when transitioning between totally separate lobby, login, and combat scene trees, avoiding bloated external file I/O operations.
*   **Plug-and-Play UI Interfaces**: Interfaces such as dynamic settings pop-ups act independently. Focus events fully rely on Godot's built-in control routing, granting zero-friction controller support across critical states like Game Over displays.

### Complete File Structure
The environment is sectioned cleanly into operational boundaries:
```text
whgame_Tetris-godot/
├── assets/                  # Art resources, sprites, and fonts
├── audio/                   # SFX files (.wav) and looped music (.ogg)
├── docs/                    # Structural documentation and architecture guides
├── lang/                    # Localization map files using Godot's CSV bindings
├── scenes/                  # `.tscn` instantiation nodes and structural prefabs
│   ├── ui/                  # Logins, Lobby menus, encapsulated Settings trees
│   └── game.tscn            # Topmost battle stage framework 
├── scripts/                 # Under-the-hood structural logic
│   ├── core/                # Falling pieces, GameState autoloads, SRS matrices
│   ├── input/               # DAS/ARR delay execution nodes targeting controllers
│   ├── game/                # Mathematical score calculation and game progression 
│   └── ui/                  # Flow management and state changes
└── project.godot            # Application manifest and strict controller mappings
```

### Core Code Logic & Modern Mechanics

#### Super Rotation System (SRS) Implementation
Developed to tightly execute guidelines rotation phases (0, R, 2, L) for the baseline set of 7 tetriminos.
*   **Wall Kicks**: Should an action push a block into obstructions, the system actively queries mapped 2D physical offset arrays. J, L, S, T, and Z pieces refer to a 3x3 origin set, whereas the 'I' piece resolves through heavily extended independent push-back formulas. All coordinates invert cleanly translating against Godot's standard downward positive Y-axis physics scale.

#### Modern Tetris Features
*   **Lock Delay Grace Limit**: Pieces encountering resting floors engage a 0.5s float phase rather than locking immediately. Move Resets permit extending duration via movement or shifts, firmly bounded by a 'Max Resets' 15 actions limiter upon equal heights.
*   **Hold Queue Restrictions**: Users can shunt the focal piece off-board to swap, immediately disabling the element until a subsequent drop. Prevents looping abuse and ensures returned blocks revert completely to the native Stage 0 axis shape.
*   **7-Bag Distribution Pattern**: Scraps raw chaotic RNG generators completely. Utilizes a shuffle bag algorithm dispensing pure groups of the seven standard pieces, negating frustrating drought patterns during fast-play.
*   **Garbage Queuing Combat Engine**:
    *   Damage generation relies on accurate multiplier arrays scaling upward from singles up toward B2B (Back-To-Back) chains, T-Spin combos, and Perfect Clears.
    *   **Red Warning Queue**: Ingressing garbage lines pool visually before striking. This mechanic gifts players an urgent neutralization phase; countering utilizing offensive strikes works as an aegis buffer cancelling incoming rows out actively prior to lockdown.
