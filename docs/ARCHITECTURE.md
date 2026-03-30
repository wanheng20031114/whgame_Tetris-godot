# WIDE TETRIS — 场景与代码架构 (Architecture)

本文档专注于记录 WIDE TETRIS 的技术堆栈、节点关系、引擎结构规范以及持久化与通讯管理模式。

---

## 1. 核心架构原则

| 类别 | 实现方式 | 理由 |
|------|---------|------|
| **可视节点** | 场景树 `.tscn` + `@onready` / `unique_name_in_owner` | 可在编辑器中可视化调整，低耦合 |
| **纯逻辑类** | `RefCounted` 引用计数基座下建立 `.new()` | 无视觉表现，不占用场景树负担 |
| **可调参数** | `@export` + `@export_group` | 检查器面板极致化分组归类，方便非程控策划随时调试手感 |
| **背景/面板** | `ColorRect` / `TextureButton` / `Panel` | 代替复杂的底层 `_draw()` 重建界面体系 |
| **音效** | 各类 `AudioStreamPlayer` 的拆解 | 可在检查器中无损替换，并在管理器中挂置统一 AudioBus |
| **动态速率** | 手持 `delta` 单帧累加器 | 由于重力下落速度是时刻变化的抛物线或断点变速体系，不适合交送内置 Timer 死板控制 |
| **内存单例传递** | 依靠 `/root/GameState` 类的 `Autoload` 内存悬挂 | 在切换庞大主干场景树（如跳转大厅和战局）期间存放必要状态（如 `player_name` 等），而不去强行污染存写硬盘配置文件，规避时序逻辑断裂问题 |
| **热插拔 UI 组件** | 将 Settings 图标封装为带有独立根目录画面的 `.tscn` | 完美摒弃传统开发中为了“无论何地都能点出设置窗口”而导致的全局 AutoLoad UI 层级污染，转为按需热植入到每个对应父节点树下，彻底释放内存控制权 |

---

## 2. 工程模块划分与文件结构

```text
whgame_Tetris-godot/
├── audio/                   # 游戏各类音效和音乐
├── docs/                    # 引擎外部分享文件 (含机制说明与开发手记)
├── lang/                    # Godot CSV 多语言包体系表
├── scenes/                  # `.tscn` 切片化节点组装预制件聚集地
│   ├── ui/                  
│   │   ├── main.tscn        # 整个前置交互界面的「源起始 Root」。它携带大厅与登入。
│   │   ├── login_screen.tscn
│   │   ├── main_lobby.tscn  
│   │   └── settings_menu.tscn # 被封装好的「带自身遮罩的全功能设置悬浮窗及齿轮按钮」
│   └── game.tscn            # 最顶级的马拉松对战与核心逻辑承接框
├── scripts/
│   ├── core/                # (下落块实体、逻辑盘、SRS驱动与单机状态机、全局悬挂 GameState)
│   ├── input/               # (DAS/ARR 处理)
│   ├── game/                # (得分，主程驱动)
│   └── ui/                  # (界面控制流，UI Manager)
└── project.godot            # 包含全部宏与输入表
```

---

## 3. 全局 AutoLoads 与通讯管理

为实现不同重场景树加载时的顺滑交互体验，我们采取了极为精简的单例常驻策略。

### GameState (`scripts/core/game_state.gd`)

这是一个只有几行属性的纯净空节点。它存在于引擎的最上方根目录 `/root/GameState` 中立而不衰。
当一盘游戏结束，需要重新载入 `ui_manager` 的大厅世界树时：

*由于重切场景，先前的所有旧变量均被抹平销毁。`ui_manager.gd` 初始化时将去敲门检查 GameState 内是否有缓存留下的玩家代号（`player_name`）。若确认内存内存在信息，便无需再强行开启一遍账号登入界面，实现了完美免扰过境跳转回 Lobby 大厅的功能。相比之下每次向物理硬盘（`settings.cfg`）发起写读取请求极其冗杂且缺乏跨网络适应性！*

---

## 4. 极致剥离的 `game.tscn` 游戏场景树细节

```text
GameScene (Node2D) — 主引擎 game_scene.gd
│
├── CustomBackground (TextureRect)      ← 背景图全拉伸铺底
├── HoldPanel (Panel + StyleBoxFlat)    ← 圆角拟态
├── NextPanel (Panel + StyleBoxFlat)    ← 辅助显示玻璃容器
├── Board (Node2D) — 棋盘计算器 board.gd
│   ├── GhostPiece (Node2D) — 探影器
│   └── CurrentPiece (Node2D) — 当前掌控体
│
├── NextPieces (Node2D)                 ← Next0 ~ Next4 承装盒子组
├── HUD (CanvasLayer)
│   ├── 内部携带各类分数标签 (Label)
│   └── GameOverPanel (PanelContainer)  ← 只在游戏失败时经代码拉起的结算浮层盒子
│       └── btn_restart / btn_return
│
├── LockDelayTimer (Timer)              ← 缓冲地着床防倒数时钟
└── BGM 与 各类 Sfx (AudioStreamPlayer) ← 按需唤起
```

### GameOver 与全环境手柄原生焦点接管支持

在 `HUD` 被拉升出“死局结算”遮罩层时，所有的按键将经由代码挂起不再流入俄罗斯方块移动。
* 代码调用 `grab_focus()` 赋力于 `btn_restart` 首按钮。
* 由于所有的控制 UI 归属在原生的纵向 Container 里，Godot 的底层焦点引擎开启后，只需轻推一次摇杆十字键位或方向键，引擎就会自动将光圈框入下一个邻近的可点击控制源上。
* 当系统捕获到确认输入（挂在 InputMap `game_over_restart` 和 `game_over_return` 以及内建 `ui_accept` 或 `ui_cancel`）它均会被自动捕获和解析成点击效果并切换环境返回至主菜单域 `main.tscn`。

---

## 5. 导出属性配置组 (@export Variables)

利用装饰器和配置注入分离机制，引擎为各逻辑提供了独立微调空间：
*(详细参数与数值表可通过游戏内界面检阅)*

**针对 GameScene**
- `spawn_col` (方块出生的 X 列下标设置)
- `starting_level` 
- `das_delay` / `arr_interval` 
- `soft_drop_multiplier` 
- `max_lock_resets` (防无尽旋转赖皮的最大触底踢次数重置)

**针对 Board**
- `columns` / `visible_rows`
- `cell_size`

## 6. 音频格式限制准绳

> ⚠️ Godot **严禁使用 `.m4a`** 格式以规避兼容和流构建重包问题。支持且允许使用的标准：
> - `.wav` — 无损音爆等，首选清脆效音
> - `.ogg` (OGG Vorbis) — 高度打包与有损缩进，专门给 BGM 层运用为主
