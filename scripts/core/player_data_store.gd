class_name PlayerDataStore
extends RefCounted

## 玩家数据持久化存储工具
##
## 提供静态方法，将采集到的游戏数据保存为明文JSON文件。
## 存储位置：exe同目录下的 userdata/ 文件夹（开发模式回退到 user://userdata/）
## 文件结构：
##   userdata/
##     ├── stats.json           — 累计统计数据
##     ├── DATA_README.md       — 中日英三语数据说明文档
##     └── sessions/
##         └── session_XXXX.json — 单场游戏快照

# ==============================================================================
# 路径常量
# ==============================================================================

## userdata 根文件夹名
const USERDATA_DIR_NAME: String = "userdata"
## sessions 子文件夹名
const SESSIONS_DIR_NAME: String = "sessions"
## 累计统计文件名
const STATS_FILE_NAME: String = "stats.json"
## 数据说明文档文件名
const README_FILE_NAME: String = "DATA_README.md"

## 历史记录最多保留的条目数（避免 stats.json 无限增长）
const MAX_HISTORY_ENTRIES: int = 500

# ==============================================================================
# 路径工具
# ==============================================================================

## 获取 userdata 根目录的绝对路径。
## 正式发布（导出后）：exe 同目录下的 userdata/
## 开发模式（编辑器中运行）：user://userdata/
static func get_data_dir() -> String:
	if OS.has_feature("editor"):
		# 编辑器中运行 → user:// 路径
		return "user://userdata"
	else:
		# 导出后 → exe 同目录
		var exe_dir: String = OS.get_executable_path().get_base_dir()
		return exe_dir.path_join(USERDATA_DIR_NAME)


## 获取 sessions 子目录路径。
static func get_sessions_dir() -> String:
	return get_data_dir().path_join(SESSIONS_DIR_NAME)


## 获取 stats.json 文件路径。
static func get_stats_path() -> String:
	return get_data_dir().path_join(STATS_FILE_NAME)


## 确保目录存在（递归创建）。
static func _ensure_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		var err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			push_error("[PlayerDataStore] 无法创建目录: %s (错误: %s)" % [dir_path, error_string(err)])


# ==============================================================================
# 保存单场会话
# ==============================================================================

## 将一场完整的会话数据保存到 sessions/ 目录。
## session_data: 由 PlayerDataCollector.end_session() 返回的字典。
static func save_session(session_data: Dictionary) -> void:
	var sessions_dir: String = get_sessions_dir()
	_ensure_dir(sessions_dir)

	# 文件名使用会话ID（ISO时间戳），替换冒号为连字符以兼容Windows文件名
	var session_id: String = session_data.get("session_id", "unknown")
	var safe_id: String = session_id.replace(":", "-")
	var file_path: String = sessions_dir.path_join("session_%s.json" % safe_id)

	var json_str: String = JSON.stringify(session_data, "\t")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("[PlayerDataStore] 无法写入会话文件: %s (错误: %s)" % [
			file_path, error_string(FileAccess.get_open_error())
		])
		return
	file.store_string(json_str)
	file.close()

	# 确保三语说明文档存在
	_ensure_readme()

	print("[PlayerDataStore] 会话已保存: %s (%d 条快照)" % [
		file_path, session_data.get("snapshots", []).size()
	])


# ==============================================================================
# 累计统计
# ==============================================================================

## 加载累计统计数据。如果文件不存在，返回默认空结构。
static func load_stats() -> Dictionary:
	var path: String = get_stats_path()
	if not FileAccess.file_exists(path):
		return _default_stats()

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[PlayerDataStore] 无法读取统计文件: %s" % path)
		return _default_stats()

	var content: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result: Error = json.parse(content)
	if parse_result != OK:
		push_warning("[PlayerDataStore] 统计文件解析失败: %s" % path)
		return _default_stats()

	return json.data if json.data is Dictionary else _default_stats()


## 更新累计统计数据（读取→合并→写回）。
## history_entry: 本场摘要数据
## radar_scores: 本场雷达图评分
static func update_stats(player_name: String, history_entry: Dictionary, radar_scores: Dictionary) -> void:
	var stats: Dictionary = load_stats()
	var data_dir: String = get_data_dir()
	_ensure_dir(data_dir)

	# ── 更新基础字段 ──
	stats["player_name"] = player_name
	stats["total_games"] = stats.get("total_games", 0) + 1
	stats["total_play_time_seconds"] = stats.get("total_play_time_seconds", 0.0) + history_entry.get("duration_seconds", 0.0)
	stats["total_pieces_placed"] = stats.get("total_pieces_placed", 0) + history_entry.get("pieces_placed", 0)
	stats["total_lines_cleared"] = stats.get("total_lines_cleared", 0) + history_entry.get("lines", 0)

	# ── 更新最佳纪录 ──
	var score: int = history_entry.get("score", 0)
	if score > stats.get("best_score", 0):
		stats["best_score"] = score
	var lines: int = history_entry.get("lines", 0)
	if lines > stats.get("best_lines", 0):
		stats["best_lines"] = lines
	var pps: float = history_entry.get("pps", 0.0)
	if pps > stats.get("best_pps", 0.0):
		stats["best_pps"] = pps
	var apm: float = history_entry.get("apm", 0.0)
	if apm > stats.get("best_apm", 0.0):
		stats["best_apm"] = apm

	# ── 更新雷达图评分（使用指数移动平均 EMA，α=0.3，给新数据较大权重） ──
	var ema_alpha: float = 0.3
	var existing_radar: Dictionary = stats.get("radar_scores", {
		"speed": 0.0, "attack": 0.0, "efficiency": 0.0,
		"topology": 0.0, "holes": 0.0, "vision": 0.0
	})
	var updated_radar: Dictionary = {}
	for key in ["speed", "attack", "efficiency", "topology", "holes", "vision"]:
		var old_val: float = float(existing_radar.get(key, 0.0))
		var new_val: float = float(radar_scores.get(key, 0.0))
		# 如果是第一场游戏（旧值为0且只有1场），直接采用新值
		if stats["total_games"] <= 1:
			updated_radar[key] = snapped(new_val, 0.1)
		else:
			updated_radar[key] = snapped(old_val * (1.0 - ema_alpha) + new_val * ema_alpha, 0.1)
	stats["radar_scores"] = updated_radar

	# ── 追加历史条目（限制最大数量） ──
	if not stats.has("history"):
		stats["history"] = []
	var history: Array = stats["history"]
	history.append(history_entry)
	# 超出上限时丢弃最早的记录
	while history.size() > MAX_HISTORY_ENTRIES:
		history.pop_front()
	stats["history"] = history

	# ── 写入磁盘 ──
	var json_str: String = JSON.stringify(stats, "\t")
	var file := FileAccess.open(get_stats_path(), FileAccess.WRITE)
	if file == null:
		push_error("[PlayerDataStore] 无法写入统计文件: %s" % get_stats_path())
		return
	file.store_string(json_str)
	file.close()

	print("[PlayerDataStore] 累计统计已更新: %s" % get_stats_path())


## 获取所有历史会话文件列表（按文件名排序）。
static func get_all_session_files() -> Array:
	var dir_path: String = get_sessions_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		return []

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return []

	var files: Array = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and fname.ends_with(".json"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files


# ==============================================================================
# 默认统计结构
# ==============================================================================

static func _default_stats() -> Dictionary:
	return {
		"player_name": "",
		"total_games": 0,
		"total_play_time_seconds": 0.0,
		"total_pieces_placed": 0,
		"total_lines_cleared": 0,
		"best_score": 0,
		"best_lines": 0,
		"best_pps": 0.0,
		"best_apm": 0.0,
		"radar_scores": {
			"speed": 0.0,
			"attack": 0.0,
			"efficiency": 0.0,
			"topology": 0.0,
			"holes": 0.0,
			"vision": 0.0
		},
		"history": []
	}


# ==============================================================================
# 三语数据说明文档
# ==============================================================================

## 确保 DATA_README.md 存在于 userdata/ 根目录。
## 如果已存在则不覆盖（允许用户手动编辑）。
static func _ensure_readme() -> void:
	var readme_path: String = get_data_dir().path_join(README_FILE_NAME)
	if FileAccess.file_exists(readme_path):
		return

	var content: String = _build_readme_content()
	var file := FileAccess.open(readme_path, FileAccess.WRITE)
	if file == null:
		push_warning("[PlayerDataStore] 无法创建说明文档: %s" % readme_path)
		return
	file.store_string(content)
	file.close()


## 构建三语数据说明文档内容。
static func _build_readme_content() -> String:
	return """# WIDE TETRIS — Player Data Documentation
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
"""
