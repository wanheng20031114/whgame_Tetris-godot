# WIDE TETRIS — Player Data Documentation
# WIDE TETRIS — 玩家数据说明文档
# WIDE TETRIS — プレイヤーデータ説明書

---

## 📁 File Structure / 文件结构 / ファイル構成

```
userdata/
├── stats.json           — Cumulative statistics / 累计统计 / 累積統計
├── DATA_README.md       — This file / 本文件 / このファイル
└── sessions/
    └── session_XXXX.json — Per-game snapshots / 单场快照 / ゲームごとのスナップショット
```

---

## 📊 stats.json — Cumulative Statistics / 累计统计 / 累積統計

| Field | Description (EN) | 说明 (ZH) | 説明 (JA) |
|-------|-------------------|-----------|-----------|
| player_name | Player name | 玩家名 | プレイヤー名 |
| total_games | Total games played | 总游戏数 | 総ゲーム数 |
| total_play_time_seconds | Total play time (seconds) | 累计游玩时间（秒） | 累計プレイ時間（秒） |
| total_pieces_placed | Total pieces placed | 累计放置方块数 | 累積配置ピース数 |
| total_lines_cleared | Total lines cleared | 累计消行数 | 累積消去ライン数 |
| best_score | Highest score ever | 历史最高分 | 歴代ハイスコア |
| best_lines | Most lines in a single game | 单场最多消行 | 1ゲーム最多ライン数 |
| best_pps | Best PPS (Pieces Per Second) | 最佳PPS（每秒落块） | 最高PPS（秒間ピース数） |
| best_apm | Best APM (Attack Per Minute) | 最佳APM（每分钟攻击） | 最高APM（分間攻撃数） |
| radar_scores | Hexagram radar chart scores | 六芒星雷达图评分 | 六芒星レーダーチャートスコア |
| history | Recent game history array | 近期游戏历史数组 | 最近のゲーム履歴配列 |

---

## 🎯 Radar Chart Dimensions / 雷达图维度 / レーダーチャート次元

| Dimension | EN | ZH | JA | Metric | Range |
|-----------|-----|-----|-----|--------|-------|
| speed | Speed | 攻速 | 速度 | PPS (Pieces Per Second) | 0-100 |
| attack | Attack | 火力 | 火力 | APM (Attack Per Minute) | 0-100 |
| efficiency | Efficiency | 效率 | 効率 | APP + KPP (Finesse) | 0-100 |
| topology | Topology | 拓扑 | トポロジー | Board flatness (DT Features) | 0-100 (reserved) |
| holes | Holes | 空洞 | ホール | Hole avoidance score | 0-100 (reserved) |
| vision | Vision | 视野 | ビジョン | Decision quality vs AI | 0-100 (reserved) |

### Calculation Details / 计算公式 / 計算式

**Speed (攻速/速度)**:
- PPS = pieces_placed / duration_seconds
- Score = clamp(PPS / 3.0, 0, 1) × 100

**Attack (火力)**:
- APM = total_damage / (duration_seconds / 60)
- Score = clamp(APM / 120, 0, 1) × 100

**Efficiency (效率)**:
- APP = total_damage / pieces_placed
- KPP = total_key_presses / pieces_placed
- APP_score = clamp(APP / 1.0, 0, 1) × 100
- KPP_score = clamp((6 - KPP) / (6 - 2), 0, 1) × 100
- Efficiency = 0.6 × APP_score + 0.4 × KPP_score

---

## 📷 Session Snapshots / 单场快照 / ゲームスナップショット

Each `session_XXXX.json` contains detailed per-piece data.
每个 `session_XXXX.json` 包含每块方块的详细数据。
各 `session_XXXX.json` にはピースごとの詳細データが含まれます。

### Session Metadata / 会话元数据 / セッションメタデータ

| Field | Description (EN) | 说明 (ZH) | 説明 (JA) |
|-------|-------------------|-----------|-----------|
| player_name | Player name | 玩家名 | プレイヤー名 |
| session_id | Session identifier (ISO timestamp) | 会话ID（ISO时间戳） | セッションID（ISOタイムスタンプ） |
| start_time | Game start time | 游戏开始时间 | ゲーム開始時刻 |
| end_time | Game end time | 游戏结束时间 | ゲーム終了時刻 |
| duration_seconds | Game duration | 游戏时长（秒） | ゲーム時間（秒） |
| final_score | Final score | 最终分数 | 最終スコア |
| final_level | Final level | 最终等级 | 最終レベル |
| final_lines | Total lines cleared | 最终消行数 | 最終消去ライン数 |
| pps | Pieces Per Second | 每秒落块 | 秒間ピース数 |
| apm | Attack Per Minute | 每分钟攻击 | 分間攻撃数 |
| app | Attack Per Piece | 每块攻击 | ピースあたり攻撃 |
| kpp | Keys Per Piece | 每块按键 | ピースあたりキー数 |

### Per-Piece Snapshot / 每块快照 / ピースごとのスナップショット

| Field | Description (EN) | 说明 (ZH) | 説明 (JA) |
|-------|-------------------|-----------|-----------|
| piece_index | Piece sequence number (0-based) | 方块序号（从0开始） | ピース番号（0始まり） |
| timestamp_ms | Time since game start (ms) | 从游戏开始经过的时间（毫秒） | ゲーム開始からの経過時間（ミリ秒） |
| piece_type | Piece type (I/O/T/S/Z/J/L) | 方块类型 | ピースタイプ |
| rotation | Rotation state (0-3) | 旋转状态 | 回転状態 |
| col | Landing column | 落地列 | 着地列 |
| row | Landing row | 落地行 | 着地行 |
| board_state | 10×20 board grid after placement | 落地后的10×20棋盘状态 | 配置後の10×20盤面状態 |
| next_pieces | Next 5 pieces in queue | 接下来5个方块 | 次の5つのピース |
| score | Score after this piece | 当前总分 | 現在のスコア |
| level | Current level | 当前等级 | 現在のレベル |
| lines_cleared | Total lines cleared so far | 累计消行数 | 累積消去ライン |
| combo | Current combo count | 当前连击数 | 現在のコンボ数 |
| b2b | Current back-to-back count | 当前背靠背计数 | 現在のB2Bカウント |
| is_spin | Whether this was a spin clear | 是否为旋转消除 | スピン消去かどうか |
| is_t_spin | Whether this was a T-spin | 是否为T-Spin | T-Spinかどうか |
| lines_cleared_this_lock | Lines cleared on this placement | 本次落锁消行数 | 今回の配置消去ライン数 |
| damage_this_lock | Attack damage dealt | 本次造成的攻击伤害 | 今回の攻撃ダメージ |
| key_presses_this_piece | Key presses for this piece | 本块按键次数 | このピースのキー入力回数 |
| hold_used | Whether hold was used | 是否使用了暂存 | ホールド使用の有無 |
| elapsed_since_last_piece_ms | Time since previous piece lock (ms) | 距上一块落锁的时间（毫秒） | 前のピース配置からの経過時間（ミリ秒） |

### Board State Values / 棋盘状态值 / 盤面状態値

| Value | Meaning (EN) | 含义 (ZH) | 意味 (JA) |
|-------|--------------|-----------|-----------|
| -1 | Empty cell | 空格 | 空セル |
| -2 | Garbage block | 垃圾行方块 | お邪魔ブロック |
| 0 | I piece | I方块 | Iピース |
| 1 | O piece | O方块 | Oピース |
| 2 | T piece | T方块 | Tピース |
| 3 | S piece | S方块 | Sピース |
| 4 | Z piece | Z方块 | Zピース |
| 5 | J piece | J方块 | Jピース |
| 6 | L piece | L方块 | Lピース |

---

*This file is auto-generated by WIDE TETRIS. You may edit it freely.*
*本文件由 WIDE TETRIS 自动生成。您可以自由编辑。*
*このファイルは WIDE TETRIS が自動生成しました。自由に編集できます。*
