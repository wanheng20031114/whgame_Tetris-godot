class_name AssistantConfig
extends RefCounted
## Future remote assistant configuration. Loading this resource never makes a request.

const ENV_KEYS: Array[String] = ["AI_API_KEY", "AI_API_BASE_URL", "AI_MODEL"]
const PROJECT_ENV_PATH := "res://.env"

var api_key: String = ""
var api_base_url: String = ""
var model: String = ""


static func load_configuration() -> AssistantConfig:
	var values: Dictionary = {}
	if OS.is_debug_build() or Engine.is_editor_hint():
		values = _read_project_env()
	# Explicit process environment values take precedence, including empty values.
	for key in ENV_KEYS:
		if OS.has_environment(key):
			values[key] = OS.get_environment(key).strip_edges()
	var config := AssistantConfig.new()
	config.api_key = str(values.get("AI_API_KEY", ""))
	config.api_base_url = str(values.get("AI_API_BASE_URL", ""))
	config.model = str(values.get("AI_MODEL", ""))
	return config


func is_configured() -> bool:
	return not api_key.is_empty() and not api_base_url.is_empty() and not model.is_empty()


static func _read_project_env() -> Dictionary:
	if not FileAccess.file_exists(PROJECT_ENV_PATH):
		return {}
	var file := FileAccess.open(PROJECT_ENV_PATH, FileAccess.READ)
	if file == null:
		return {}
	var values: Dictionary = {}
	while not file.eof_reached():
		var line := file.get_line().trim_prefix("\ufeff").strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var separator := line.find("=")
		if separator < 0:
			continue
		var key := line.left(separator).strip_edges()
		if key not in ENV_KEYS:
			continue
		var value := line.substr(separator + 1).strip_edges()
		if value.length() >= 2:
			var double_quoted := value.begins_with('"') and value.ends_with('"')
			var single_quoted := value.begins_with("'") and value.ends_with("'")
			if double_quoted or single_quoted:
				value = value.substr(1, value.length() - 2)
		values[key] = value
	file.close()
	return values
