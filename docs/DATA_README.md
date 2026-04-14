# WIDE TETRIS 数据说明（DATA_README）

本文档用于说明 `userdata/` 下玩家数据的结构、字段意义与评分计算方式。
目标是让玩家或开发者可以仅通过此文档，完整理解“每局数据”和“玩家总数据”的含义。

## 1. 数据目录

```text
userdata/
├─ DATA_README.md
├─ stats.json
└─ sessions/
   ├─ session_2026-04-08T10-15-30.json
   └─ ...
```

- `sessions/session_*.json`：单局详细数据（按局存档）
- `stats.json`：玩家总览统计与历史摘要（跨局累计）
- `DATA_README.md`：本说明文档

## 2. 生成与更新流程

1. 每次单局结束，采集器会产出 `session_data`。
2. `session_data` 写入 `sessions/session_*.json`。
3. 同时生成该局 `history_entry`，并更新 `stats.json`。
4. 若 `userdata/DATA_README.md` 不存在，则写入说明文件。

对应代码：
- 单局落盘：`scripts/core/player_data_collector.gd` -> `PlayerDataStore.save_session(...)`
- 总数据更新：`scripts/core/player_data_store.gd` -> `update_stats(...)`
- README 写入：`scripts/core/player_data_store.gd` -> `_ensure_readme()`

## 3. 单局文件（sessions/session_*.json）

### 3.1 顶层字段

- `player_name`：玩家名
- `session_id`：局 ID（ISO 时间）
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
- `discarded_snapshots`：内存保护导致被丢弃的快照数量
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
- `rotation` / `col` / `row`：落锁姿态与位置
- `board_state`：10x20 可见棋盘二维数组（空格为 `-1`）
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
