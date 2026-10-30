class_name Handling
extends RefCounted

## 操作手感参数（与 TETR.IO 的 HANDLING 设置一致，单位同为帧 @60fps）
## DAS: 自动移动延迟  ARR: 自动移动间隔(0=瞬移)  SDF: 软降倍率(41=∞)  DCD: 旋转贴墙后的 DAS 截断

const SECTION := "Handling"
const FRAME := 1.0 / 60.0
const SDF_INSTANT := 41.0

const DEFAULTS := {"das": 10.0, "arr": 2.0, "sdf": 6.0, "dcd": 1.0}
const RANGES := {
	"das": [1.0, 20.0, 0.1],
	"arr": [0.0, 5.0, 0.1],
	"sdf": [5.0, 41.0, 1.0],
	"dcd": [0.0, 20.0, 0.1],
}

static var das_frames: float = 10.0
static var arr_frames: float = 2.0
static var sdf: float = 6.0
static var dcd_frames: float = 1.0
static var _loaded: bool = false


static func settings_path() -> String:
	if OS.has_feature("editor"):
		return "res://settings.cfg"
	return OS.get_executable_path().get_base_dir().path_join("settings.cfg")


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(settings_path()) != OK:
		return
	for key in DEFAULTS:
		set_value(key, float(cfg.get_value(SECTION, key, DEFAULTS[key])))


static func get_value(key: String) -> float:
	ensure_loaded()
	match key:
		"das": return das_frames
		"arr": return arr_frames
		"sdf": return sdf
		"dcd": return dcd_frames
	return 0.0


static func set_value(key: String, value: float) -> void:
	var r: Array = RANGES.get(key, [0.0, 100.0, 1.0])
	value = clampf(value, r[0], r[1])
	match key:
		"das": das_frames = value
		"arr": arr_frames = value
		"sdf": sdf = value
		"dcd": dcd_frames = value


static func save() -> void:
	var cfg := ConfigFile.new()
	var storage_load_error := cfg.load(settings_path())
	if storage_load_error != OK and storage_load_error != ERR_FILE_NOT_FOUND:
		StorageBudget.report_error("Settings could not be read; the existing file was retained: " + error_string(storage_load_error))
		return
	for key in DEFAULTS:
		cfg.set_value(SECTION, key, get_value(key))
	var storage_save_error := cfg.save(settings_path())
	if storage_save_error != OK:
		StorageBudget.report_error("Settings could not be saved: " + error_string(storage_save_error))


static func das_seconds() -> float:
	ensure_loaded()
	return das_frames * FRAME


static func arr_seconds() -> float:
	ensure_loaded()
	return arr_frames * FRAME


static func dcd_seconds() -> float:
	ensure_loaded()
	return dcd_frames * FRAME


static func is_instant_soft_drop() -> bool:
	ensure_loaded()
	return sdf >= SDF_INSTANT


## 软降速度（格/秒）：TETR.IO 为 max(重力×SDF, 0.05G×SDF)
static func soft_drop_speed(gravity_cells_per_sec: float) -> float:
	ensure_loaded()
	return maxf(gravity_cells_per_sec * sdf, 0.05 * 60.0 * sdf)


static func format_value(key: String, value: float) -> String:
	if key == "sdf":
		return "∞" if value >= SDF_INSTANT else "%dX" % int(value)
	return ("%dF" if is_equal_approx(value, roundf(value)) else "%.1fF") % value
