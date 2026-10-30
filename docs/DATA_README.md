# TETRIS 数据说明（DATA_README）

本文档用于说明 `userdata/` 下玩家数据的结构、字段意义与评分计算方式。
目标是让玩家或开发者可以仅通过此文档，完整理解“每局数据”和“玩家总数据”的含义。

## 1. 数据目录

```text
userdata/
├─ DATA_README.md
├─ stats.json
└─ sessions/
   ├─ session_2026-04-08T10-15-30_<UUID>.json
   └─ ...
```

- `sessions/session_*.json`：单局详细数据（按局存档）
- `stats.json`：玩家总览统计与历史摘要（跨局累计）
- `DATA_README.md`：本说明文档

### 存储位置与硬上限

原型导出程序将数据放在游戏 EXE 同目录的 `userdata/`；编辑器运行使用项目目录的 `userdata/`。不会把新存档、分析器缓存或诊断日志写入用户 AppData，也不自动移动或删除旧目录内容。`settings.cfg` 继续保留在游戏 EXE 同目录（编辑器为项目根目录）。

`StorageBudget` 同时执行两级硬预算，均使用十进制字节：**单局游戏数据合计最多 1,000,000,000 字节（1 GB）**，**整个 `userdata/` 合计最多 20,000,000,000 字节（20 GB）**。同一局的 `session_<id>.json`、对应 `_analyzed.json` 及其临时文件、保留备份和预留分析输出共用该局的 1 GB；不同局分别计量。共享诊断日志、跨局统计及分析器缓存计入目录总量。全部既有文件和隐藏文件也计入预算。

写入前使用进程内互斥和跨进程写锁同时核算两级容量。一局达到 1 GB 只停止该局继续写入，其他局仍可在总额度内保存；目录达到 20 GB 后停止新增数据。两者均显示原因、保留旧文件，且不打断游戏。如果旧数据已经超过相应限额，程序不会自动删除它们以腾出空间。

| 文件或操作 | 硬上限 |
| --- | ---: |
| 单个诊断日志 | 8 MiB（8,388,608 字节）；达限停止追加，保留首次错误 |
| 单局游戏数据组（含记录、分析、临时及备份） | 1,000,000,000 字节 |
| 整个 `userdata/` | 20,000,000,000 字节 |
| 单局 session JSON | 最多 1,000,000,000 字节，并受该局剩余额度约束 |
| 单个分析结果 / 预留临时输出 | 64,000,000 字节 |
| stats.json | 4,000,000 字节 |
| 缓存的受限分析器 EXE | 64,000,000 字节 |

保存通过同目录临时文件及旧版本备份完成可恢复提交。写入或提交失败会保留旧文件并在界面显示原因；损坏的统计文件不会被当作新档覆盖。失败对局保留在当前进程内待重试队列（最多两局），达到队列上限后停止采集新录像，游戏仍可继续。未落盘的内容不能保证在强制关闭程序后保留。备份和旧 session 不自动清理；`history` 的 500 条限制仅作用于统计摘要，不会删除原始录像。

分析仅运行确认支持 `TETRIS_STORAGE_V1` 的随附单进程程序，不在游戏内调用 Cargo 或 Python。输入先检查 1 GB 文件上限，输出同时占用该局及目录预留额度，并使用逐次写入的字节计数器；用户可按 Esc 取消，120 秒硬超时或父游戏退出后终止分析。只有完整、有效结果才提交，原始录像保持不变。

磁盘容量与处理资源限制相互独立：仍最多记录/分析 10,000 个快照，单个分析结果最多 64 MB，单个诊断日志最多 8 MiB。提高总容量不意味着在内存中无限积累快照，也不保证任意接近 1 GB 的外部 JSON 都可进行分析。读取时按实际文件大小申请缓冲，避免小文件也按 1 GB 额度分配内存。

如果程序恰在持有 `.budget-write-lock` 时被强制终止，后续写入会保守拒绝并要求明确恢复；不会依据过时的 PID 观察自动删除锁。读取已存在的有限大小文件不要求剩余写预算。

## 2. 生成与更新流程

1. 每次单局结束，采集器会产出 `session_data`。
2. `session_data` 写入 `sessions/session_*.json`。
3. 同时生成该局 `history_entry`，并更新 `stats.json`。
4. 若 `userdata/DATA_README.md` 不存在，则写入说明文件。

对应代码：
- 单局落盘：`scripts/core/player_data_collector.gd` -> `PlayerDataStore.persist_session(...)`
- 总数据更新：`scripts/core/player_data_store.gd` -> `update_stats(...)`
- README 写入：`scripts/core/player_data_store.gd` -> `_ensure_readme()`

## 3. 单局文件（sessions/session_*.json）

### 3.1 顶层字段

- `player_name`：玩家名
- `session_id`：开始时间与随机 UUID 组成的唯一 ID，避免同秒开局覆盖。旧 ISO 时间 ID 的文件仍可读取。
- `start_time` / `end_time`：开局/结束时间
- `duration_seconds`：对局秒数
- `final_score` / `final_level` / `final_lines`：结算分数、等级、总消行
- `pieces_placed`：落锁方块数
- `total_damage`：总攻击（送出的垃圾量）
- `total_key_presses`：总按键数
- `pps` / `apm` / `app` / `kpp`：核心效率指标
- `singles` / `doubles` / `triples` / `tetrises`：各类消行计数
- `spin_clears` / `t_spin_clears`：旋转类消行计数
- `effective_clear_events` / `spin_clear_events` / `tetris_clear_events` / `other_clear_events`：用于视野评分的有效消除事件计数
- `max_combo` / `max_b2b`：本局最大连击与最大 B2B
- `discarded_snapshots`：到达 10,000 快照上限后未继续记录的快照数；已有快照不被丢弃，总体对局指标仍继续统计。
- `radar_scores`：六维评分（0~100）
- `snapshots`：逐落锁快照数组

### 3.2 radar_scores（六维）

- `speed`
- `attack`
- `efficiency`
- `structure`
- `stability`
- `vision`

说明：
- 旧字段 `holes` 已完全废弃。
- 当前系统统一使用 `stability`。

### 3.3 snapshots[] 字段（每次落锁一条）

- `piece_index`：本局第几个落锁方块（从 0 开始）
- `timestamp_ms`：相对开局的毫秒时间
- `piece_type`：`I/O/T/S/Z/J/L`
- `rotation` / `col` / `row`：落锁姿态与位置。`row` 使用完整棋盘坐标，包含顶部 20 行缓冲区；可见行号为 `row - 20`，因此 `row < 20` 表示仍在可见区上方，不能当作可见区底部坐标。
- `board_state_after_drop` / `board_state_after_clear`：20 行 × 10 列的可见棋盘；空格为 `0`，方块为 `1..7`，垃圾块为 `8`。
- `next_pieces`：下一个方块预览（名称数组）
- `score` / `level` / `lines_cleared`：落锁后状态
- `combo` / `b2b`：连击状态
- `is_spin` / `is_t_spin`：是否旋转消行
- `lines_cleared_this_lock`：本次落锁消行数
- `damage_this_lock`：本次落锁攻击
- `key_presses_this_piece`：本块使用的按键数
- `hold_used`：本块是否使用 Hold
- `elapsed_since_last_piece_ms`：与上次落锁的时间间隔
- `structure_score` / `stability_score`：该落锁时棋盘结构评分

## 4. 玩家总数据（stats.json）

### 4.1 顶层字段

- `player_name`
- `total_games`
- `total_play_time_seconds`
- `total_pieces_placed`
- `total_lines_cleared`
- `best_score` / `best_lines` / `best_pps` / `best_apm`
- `radar_scores`：六维长期能力值（EMA 平滑）
- `history`：最近对局摘要（最多 500 条）

### 4.2 history[] 字段

- `session_id`
- `date`
- `score` / `lines` / `level`
- `duration_seconds`
- `pps` / `apm` / `app` / `kpp`
- `structure` / `stability`
- `pieces_placed`

### 4.3 EMA 更新规则

`stats.radar_scores` 不是直接覆盖，而是指数移动平均：

- `ema_alpha = 0.3`
- 首局：直接采用首局分值
- 后续：`new = old * (1 - alpha) + current * alpha`

这样可以减少单局波动，反映长期能力趋势。

## 5. 六维评分定义

### 5.1 Speed（速度）

- 指标：`PPS = pieces_placed / duration_seconds`
- 评分：`clamp(PPS / 3.0, 0, 1) * 100`

### 5.2 Attack（攻击）

- 指标：`APM = total_damage / (duration_seconds / 60)`
- 评分：`clamp(APM / 120.0, 0, 1) * 100`

### 5.3 Efficiency（效率）

- `APP = total_damage / pieces_placed`
- `KPP = total_key_presses / pieces_placed`
- `APP_score = clamp(APP / 1.0, 0, 1) * 100`
- `KPP_score = clamp((6.0 - KPP) / (6.0 - 2.0), 0, 1) * 100`
- `efficiency = 0.6 * APP_score + 0.4 * KPP_score`

### 5.4 Structure（结构）

由 `StructureEvaluator` 基于 10x20 棋盘计算：

- `empty_regions`：空区连通域数量（包含顶部虚拟空行）
- `trapped_cells`：从顶部不可达的封闭空格数量
- `flatness_score`：地形平整分
- `structure_score = 0.65 * flatness_score + 0.35 * stability_score`

### 5.5 Stability（稳定）

稳定分用于衡量“空洞与碎片化风险”：

- `stability_score = 100 - min(100, trapped_cells * 2 + max(0, empty_regions - 1) * 12)`
- 再钳制到 `0~100`
- 越高表示棋形越稳定（封闭空洞更少、碎片化更低）

### 5.6 Vision（视野）

根据“有效消除构成比例”估计玩家大局视野：

- 有效事件：`lines_cleared_this_lock > 0`
- 三类占比：
  - `spin_ratio`（Spin 类）
  - `tetris_ratio`（四消类）
  - `other_ratio`（其余有效消除）
- 使用目标区间打分并加权：
  - `spin` 目标 `30%~50%`（权重 0.45）
  - `tetris` 目标 `20%~40%`（权重 0.30）
  - `other` 目标 `20%~40%`（权重 0.25）
- 结合样本量置信度：短局会向 50 分回归，避免误判

## 6. 示例结构（简化）

```json
{
  "player_name": "Player",
  "total_games": 12,
  "radar_scores": {
    "speed": 41.2,
    "attack": 28.7,
    "efficiency": 35.9,
    "structure": 72.6,
    "stability": 32.9,
    "vision": 54.3
  },
  "history": [
    {
      "session_id": "2026-04-08T00:47:23",
      "score": 65842,
      "lines": 89,
      "pps": 1.21,
      "apm": 11.3,
      "app": 0.16,
      "kpp": 4.62,
      "structure": 72.6,
      "stability": 32.9,
      "pieces_placed": 250
    }
  ]
}
```

## 7. 编码约定

- 文本编码：UTF-8（建议无 BOM）
- 换行：LF

如出现乱码，优先检查编辑器是否误存为其他编码（如 ANSI/GBK/UTF-16）。
