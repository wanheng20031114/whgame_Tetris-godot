# ==========================================
# PlayerDataStore (玩家数据存储模块)
# 
# 文件整体作用：
# 此文件是一个静态数据存储管理类（PlayerDataStore），主要负责：
# 1. 路径管理：管理玩家游戏本地数据的存储目录路径（区分编辑器环境和打包后的正式环境）。
# 2. 单局记录：将玩家的单局游戏数据（Session）自动以 JSON 格式保存到本地磁盘。
# 3. 全局统计：汇总并计算玩家的整体统计数据（Stats），例如总游戏时长、总落块数、总消除行数，记录最高分、最大连击等。
# 4. 雷达图管理：利用指数移动平均（EMA）等算法，对玩家的六维能力（速度、攻击、效率、结构、稳定性、视野）进行平滑和持久化存储。
# 5. 历史记录管理：维护一个支持最多 500 条近期游戏快照的历史记录队列，超出部分会自动弹出。
# 
# 该类所有的方法均为 static（静态方法），在全剧中可以直接通过 PlayerDataStore.方法名() 调用，无需实例化。
# ==========================================
class_name PlayerDataStore
extends RefCounted

# --- 常量定义 ---
# 根目录名称
const USERDATA_DIR_NAME: String = "userdata"
# 单局数据内部目录名称
const SESSIONS_DIR_NAME: String = "sessions"
# 全局统计文件名称
const STATS_FILE_NAME: String = "stats.json"
# 根目录下的说明文件名称
const README_FILE_NAME: String = "DATA_README.md"
const DOCS_README_PATH: String = "res://docs/DATA_README.md"
# 最大允许保存的历史对局记录数目，防止存储无限膨胀
const MAX_HISTORY_ENTRIES: int = 500


# ==========================================
# get_data_dir()
# 
# 作用：获取保存所有游戏用户数据的根目录路径。
# 逻辑：
# - 如果是在游戏引擎编辑器环境（editor）下运行，则保存在项目路径的 "res://userdata" 中。
# - 如果是已经打包部署的独立执行文件，则保存在与 (.exe) 同级的 "userdata" 目录中。
# 返回：一个用于存储数据的绝对或者引擎内表示的根目录字符串路径。
# ==========================================
static func get_data_dir() -> String:
	if OS.has_feature("editor"):
		return "res://userdata"
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	return exe_dir.path_join(USERDATA_DIR_NAME)


# ==========================================
# get_sessions_dir()
# 
# 作用：获取单局对局详细数据的专属存放文件夹路径。
# 依赖：调用了 get_data_dir() 并向上拼接。
# 返回：单局 sessions 数据存放目录。
# ==========================================
static func get_sessions_dir() -> String:
	return get_data_dir().path_join(SESSIONS_DIR_NAME)


# ==========================================
# get_stats_path()
# 
# 作用：获取全局状态统计 JSON 文件的完整路径。
# 返回：包含所有综合统计数据（例如总场次、历史最佳等）的绝对或引擎相对文件路径。
# ==========================================
static func get_stats_path() -> String:
	return get_data_dir().path_join(STATS_FILE_NAME)


static func ensure_data_dirs() -> void:
	_ensure_dir(get_data_dir())
	_ensure_dir(get_sessions_dir())
	_ensure_readme()


# ==========================================
# _ensure_dir(dir_path)
# 
# 作用：这是一个内部辅助工具函数，用于确保某个指定的文件夹路径真实存在于用户文件系统中。
# 参数：
# - dir_path：需要验证及创建的绝对路径。
# 逻辑：
# - 如果指定的路径不存在，它会自动并级联地创建所有层级的文件夹。
# - 如果创建失败，它会通过系统控制台输出错误日志。
# ==========================================
static func _ensure_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		var err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			push_error("[PlayerDataStore] Failed to create dir: %s (%s)" % [dir_path, error_string(err)])


# ==========================================
# save_session(session_data)
# 
# 作用：将一场单局对局的所有采集数据存储为一个独立的 JSON 物理文件。
# 参数：
# - session_data：需要被保存的当场对战信息的超大字典对象（通常由外部的 collector 提供）。
# 逻辑：
# 1. 确保单局的专属 sessions 文件夹已被成功创建。
# 2. 从字典中抽取 timestamp/session_id 字段作为区分该局对战的独特名称安全 ID（替换不安全字符 ":" 为 "-"）。
# 3. 将单局对局整个字典序列化成带格式（缩进）的 JSON 字符串并写入该路径中。
# 4. 最后附带检查和生成 README 说明文件。
# ==========================================
static func save_session(session_data: Dictionary) -> void:
	var sessions_dir: String = get_sessions_dir()
	_ensure_dir(sessions_dir)

	var session_id: String = str(session_data.get("session_id", "unknown"))
	var safe_id: String = session_id.replace(":", "-")
	var file_path: String = sessions_dir.path_join("session_%s.json" % safe_id)

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("[PlayerDataStore] Failed to write session: %s (%s)" % [
			file_path, error_string(FileAccess.get_open_error())
		])
		return
	var pretty_json: String = JSON.stringify(session_data, "\t")
	file.store_string(_compact_numeric_arrays(pretty_json))
	file.close()

	_ensure_readme()


# ==========================================
# load_stats()
# 
# 作用：从磁盘上的特定路径将全局统计数据文件 "stats.json" 读取并解析至内存。
# 逻辑：
# - 如果不存在这个统计文件或者是不能正确解析，系统都会返回由 _default_stats() 提供的默认初始零值。
# - 若雷达中缺少 stability 字段，则按 0.0 处理，保证数据结构完整。
# 返回：一个代表目前最高分、操作偏好、雷达属性及历史记录的综合型统计字典。
# ==========================================
static func load_stats() -> Dictionary:
	var path: String = get_stats_path()
	if not FileAccess.file_exists(path):
		return _default_stats()

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _default_stats()

	var content: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(content) != OK:
		return _default_stats()
	if not (json.data is Dictionary):
		return _default_stats()

	var stats: Dictionary = json.data
	if not stats.has("radar_scores") or not (stats["radar_scores"] is Dictionary):
		stats["radar_scores"] = {}
	var radar: Dictionary = stats["radar_scores"]
	if not radar.has("stability"):
		radar["stability"] = 0.0
	stats["radar_scores"] = radar
	return stats


# ==========================================
# update_stats(player_name, history_entry, radar_scores)
# 
# 作用：在任意单局对决完成后，将这次结算的简明信息综合追加、更新进整体大统计数据文件内并保存至磁盘。
# 参数：
# - player_name: 当前操作的玩家名称（以备用于多账号系统留存）。
# - history_entry: 当局简单的总览概括数据字典，存有诸如结束分数、行数、时长等基本参数。
# - radar_scores: 当局中评判得出的六维雷达图得分（用来影响全局长期的雷达分布）。
# 逻辑：
# 1. 加载旧有的整体统计指标，累加总游戏次数、时间、消行数、放置碎片数等数据值。
# 2. 判断目前对局得分及指标如果大于全局的最佳分，便刷新破纪录成就 (best_score, best_lines 等)。
# 3. 对各个六项重要雷达评分，执行指数移动平均值算法（EMA：参数 ema_alpha 默认为 0.3），将新的能力分融汇入旧的能力图内，令成长更为平滑。
# 4. 追加 history_entry 数据进历史记录列项，并且实施队列限流出队控制 (超 500 条弹走最旧)。
# 5. 最后安全写入物理 JSON 文件持久化改动。
# ==========================================
static func update_stats(player_name: String, history_entry: Dictionary, radar_scores: Dictionary) -> void:
	var stats: Dictionary = load_stats()
	_ensure_dir(get_data_dir())

	stats["player_name"] = player_name
	stats["total_games"] = int(stats.get("total_games", 0)) + 1
	stats["total_play_time_seconds"] = float(stats.get("total_play_time_seconds", 0.0)) + float(history_entry.get("duration_seconds", 0.0))
	stats["total_pieces_placed"] = int(stats.get("total_pieces_placed", 0)) + int(history_entry.get("pieces_placed", 0))
	stats["total_lines_cleared"] = int(stats.get("total_lines_cleared", 0)) + int(history_entry.get("lines", 0))

	var score: int = int(history_entry.get("score", 0))
	if score > int(stats.get("best_score", 0)):
		stats["best_score"] = score
	var lines: int = int(history_entry.get("lines", 0))
	if lines > int(stats.get("best_lines", 0)):
		stats["best_lines"] = lines
	var pps: float = float(history_entry.get("pps", 0.0))
	if pps > float(stats.get("best_pps", 0.0)):
		stats["best_pps"] = pps
	var apm: float = float(history_entry.get("apm", 0.0))
	if apm > float(stats.get("best_apm", 0.0)):
		stats["best_apm"] = apm

	var ema_alpha: float = 0.3
	var existing_radar: Dictionary = stats.get("radar_scores", {
		"speed": 0.0, "attack": 0.0, "efficiency": 0.0,
		"structure": 0.0, "stability": 0.0, "vision": 0.0
	})
	if not existing_radar.has("stability"):
		existing_radar["stability"] = 0.0

	var updated_radar: Dictionary = {}
	for key in ["speed", "attack", "efficiency", "structure", "stability", "vision"]:
		var old_val: float = float(existing_radar.get(key, 0.0))
		var default_new_val: float = 0.0
		var new_val: float = float(radar_scores.get(key, default_new_val))
		if int(stats["total_games"]) <= 1:
			updated_radar[key] = snapped(new_val, 0.1)
		else:
			updated_radar[key] = snapped(old_val * (1.0 - ema_alpha) + new_val * ema_alpha, 0.1)
	stats["radar_scores"] = updated_radar

	if not stats.has("history") or not (stats["history"] is Array):
		stats["history"] = []
	var history: Array = stats["history"]
	history.append(history_entry)
	while history.size() > MAX_HISTORY_ENTRIES:
		history.pop_front()
	stats["history"] = history

	var file := FileAccess.open(get_stats_path(), FileAccess.WRITE)
	if file == null:
		push_error("[PlayerDataStore] Failed to write stats: %s" % get_stats_path())
		return
	file.store_string(JSON.stringify(stats, "\t"))
	file.close()


# ==========================================
# get_all_session_files()
# 
# 作用：向外界提供接口返回所有历史详细单局（Session）保存下来的 JSON 文件名列表。
# 逻辑：
# - 逐个枚举和检视对应的目录内容集，如果符合是文件且以 “.json” 结尾则装载进 Array 以供输出使用。
# 返回：一个单局 Session json 字符串名字组成的 Array, 会按名字自然序排列。
# ==========================================
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


# ==========================================
# _default_stats()
# 
# 作用：构建并在初次遇到未知或错误全局数据情况下建立起一套空白占位的零参数数据结构。
# 返回：一本格式完整、雷达完全清零并预置好结构的初生参数字典。
# ==========================================
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
			"structure": 0.0,
			"stability": 0.0,
			"vision": 0.0
		},
		"history": []
	}


# ==========================================
# _ensure_readme()
# 
# 作用：协助在用户的数据专属根目录下建立一个纯文本引导说明文件，声明该文件夹的作用。
# ==========================================
static func _ensure_readme() -> void:
	var readme_path: String = get_data_dir().path_join(README_FILE_NAME)
	if FileAccess.file_exists(readme_path):
		return

	var file := FileAccess.open(readme_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(_build_readme_content())
	file.close()


# ==========================================
# _build_readme_content()
# 
# 作用：以纯多语言文本多行格式的形式存放关于 userdata 文件夹的通用帮助手册文案。
# ==========================================
static func _build_readme_content() -> String:
	# userdata/DATA_README.md 的原文来源固定为 docs/DATA_README.md
	# 保证生成版与文档版保持一致。
	if FileAccess.file_exists(DOCS_README_PATH):
		var file := FileAccess.open(DOCS_README_PATH, FileAccess.READ)
		if file != null:
			var content: String = file.get_as_text()
			file.close()
			if not content.strip_edges().is_empty():
				return content

	# 兜底文本：仅在 docs 丢失或读取失败时使用。
	return """# WIDE TETRIS - Player Data

This directory stores local player statistics and per-session snapshots.
See docs/DATA_README.md for the full schema and scoring reference.
"""


static func _compact_numeric_arrays(pretty_json: String) -> String:
	var lines: PackedStringArray = pretty_json.split("\n")
	var output: PackedStringArray = []
	var i: int = 0

	while i < lines.size():
		var line: String = lines[i]
		var open_trimmed: String = line.strip_edges()
		if open_trimmed == "[":
			var compact_line: String = _try_compact_numeric_array(lines, i)
			if not compact_line.is_empty():
				output.append(compact_line)
				i = _find_array_close_index(lines, i) + 1
				continue
		output.append(line)
		i += 1

	return "\n".join(output)


static func _try_compact_numeric_array(lines: PackedStringArray, start_index: int) -> String:
	var open_line: String = lines[start_index]
	var indent: String = _leading_whitespace(open_line)
	var values: Array[String] = []
	var i: int = start_index + 1

	while i < lines.size():
		var row: String = lines[i]
		var trimmed: String = row.strip_edges()
		if trimmed == "]" or trimmed == "],":
			if values.is_empty():
				return ""
			var trailing_comma: String = "," if trimmed.ends_with(",") else ""
			return "%s[%s]%s" % [indent, ", ".join(values), trailing_comma]

		var token: String = trimmed.trim_suffix(",")
		if not _is_json_number(token):
			return ""
		values.append(token)
		i += 1

	return ""


static func _find_array_close_index(lines: PackedStringArray, start_index: int) -> int:
	var depth: int = 0
	for i in range(start_index, lines.size()):
		var trimmed: String = lines[i].strip_edges()
		if trimmed == "[":
			depth += 1
		elif trimmed == "]" or trimmed == "],":
			depth -= 1
			if depth == 0:
				return i
	return start_index


static func _leading_whitespace(text: String) -> String:
	var idx: int = 0
	while idx < text.length():
		var ch: String = text.substr(idx, 1)
		if ch != " " and ch != "\t":
			break
		idx += 1
	return text.substr(0, idx)


static func _is_json_number(token: String) -> bool:
	if token.is_empty():
		return false
	var parser := JSON.new()
	if parser.parse(token) != OK:
		return false
	return parser.data is float or parser.data is int
