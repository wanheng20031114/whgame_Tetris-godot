# WIDE TETRIS — 场景与代码架构

## 1. 核心原则

| 类别 | 实现方式 | 理由 |
|------|---------|------|
| **可视节点** | 场景树 `.tscn` + `@onready` | 可在编辑器中可视化调整 |
| **背景/面板** | `ColorRect` / `Panel` 节点 | 替代 `_draw()` 和 `RenderingServer` |
| **音效** | `AudioStreamPlayer` 节点 | 可在检查器中替换音频文件 |
| **计时器** | `Timer` 节点 + `timeout` 信号 | 利用引擎内置节能计时 |
| **纯逻辑类** | `RefCounted` + `.new()` | 无视觉表现，不该放场景树 |
| **可调参数** | `@export` + `@export_group` | 检查器面板分组显示，方便调试 |
| **动态速率** | 手动 `delta` 累加 | 重力等速度动态变化不适合 Timer |

## 2. 游戏场景树 (`scenes/game.tscn`)

```
GameScene (Node2D) — game_scene.gd
│
├── Background (ColorRect)              ← 全屏深色背景
├── HoldPanel (Panel + StyleBoxFlat)    ← 圆角深色面板
├── NextPanel (Panel + StyleBoxFlat)    ← 圆角深色面板
│
├── Board (Node2D) — board.gd
│   ├── GhostPiece (Node2D) — piece.gd
│   └── CurrentPiece (Node2D) — piece.gd
│
├── HoldPiece (Node2D) — piece.gd
├── NextPieces (Node2D)
│   └── Next0 ~ Next4 (Node2D) — piece.gd
│
├── HUD (CanvasLayer)
│   ├── HoldLabel, NextLabel (Label)
│   ├── ScoreLabel, LevelLabel, LinesLabel (Label)
│   └── GameOverLabel (Label)
│
├── LockDelayTimer (Timer)
│
├── BGM (AudioStreamPlayer)            ← 游戏启动循环播放
├── SfxPlanting (AudioStreamPlayer)    ← 方块放置时播放
├── SfxLineClear (AudioStreamPlayer)   ← 普通消行
├── SfxSuccess (AudioStreamPlayer)     ← Tetris / Spin 特殊消除
├── SfxDeath (AudioStreamPlayer)       ← 游戏结束
└── SfxClick (AudioStreamPlayer)       ← UI 按钮（预留）
```

## 3. 检查器暴露的参数 (@export)

### GameScene
| 分组 | 参数 | 默认值 | 说明 |
|------|------|--------|------|
| 游戏参数 | `spawn_col` | 4 | 方块出生列 |
| 游戏参数 | `starting_level` | 1 | 起始等级 |
| 操作手感 | `das_delay` | 0.133s | DAS 初始延迟 |
| 操作手感 | `arr_interval` | 0.010s | ARR 重复间隔 |
| 操作手感 | `soft_drop_multiplier` | 20× | 软降速度倍率 |
| 锁定延迟 | `max_lock_resets` | 15 | 最大重置次数 |

### Board
| 分组 | 参数 | 默认值 | 说明 |
|------|------|--------|------|
| 棋盘尺寸 | `columns` | 10 | 列数（WIDE 模式可改大） |
| 棋盘尺寸 | `visible_rows` | 20 | 可见行数 |
| 棋盘尺寸 | `cell_size` | 30.0 | 格子像素大小 |

### Piece
| 参数 | 默认值 | 说明 |
|------|--------|------|
| `cell_size` | 30.0 | 格子像素大小（Hold/Next 预览设为 21） |

### LockDelayTimer
| 参数 | 默认值 | 说明 |
|------|--------|------|
| `wait_time` | 0.5 | 锁定延迟时长（Timer 自带属性） |

## 4. 音频格式注意

> ⚠️ Godot 4 **不支持 .m4a** 格式。支持的格式：
> - `.wav` — 无损，音效首选
> - `.ogg` (OGG Vorbis) — 有损压缩，BGM 首选
> - `.mp3` — 有损压缩，也可用于 BGM
>
> 请将项目中的 `.m4a` 文件（bgm、planting、click）转换为 `.ogg` 格式。

## 5. 文件结构

```
whgame_Tetris-godot/
├── audio/                   # 音频资源
│   ├── bgm.ogg              # ← 需要从 .m4a 转换
│   ├── planting.ogg          # ← 需要从 .m4a 转换
│   ├── click.ogg             # ← 需要从 .m4a 转换
│   ├── line_clear.wav        # ✓ 已工作
│   ├── success.wav           # ✓ 已工作
│   └── death.wav             # ✓ 已工作
├── docs/
├── scenes/game.tscn
├── scripts/
│   ├── core/ (piece_data, piece, board, bag_randomizer)
│   ├── input/ (das_arr)
│   └── game/ (game_scene, scoring)
└── project.godot
```
