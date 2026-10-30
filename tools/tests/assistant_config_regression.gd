extends Node

## Mutates only a disposable project's dotenv and this process's environment.
const CONFIG := preload("res://scripts/ai/assistant_config.gd")
const KEYS: Array[String] = ["AI_API_KEY", "AI_API_BASE_URL", "AI_MODEL"]
const ENV_PATH := "res://.env"

var _checks := 0
var _failures := 0
var _saved_environment: Dictionary = {}


func _ready() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1" or not _is_isolated_copy():
		push_error("Assistant config regression requires a marked isolated project.")
		get_tree().quit(2)
		return
	# Refuse to inspect or overwrite any pre-existing credentials, even in a copy.
	if FileAccess.file_exists(ENV_PATH):
		push_error("Assistant config regression requires an absent .env file.")
		get_tree().quit(2)
		return
	for key in KEYS:
		_saved_environment[key] = {
			"present": OS.has_environment(key),
			"value": OS.get_environment(key),
		}
		OS.unset_environment(key)
	_run.call_deferred()


func _is_isolated_copy() -> bool:
	var marker_path := "res://.safe-run-isolated.json"
	if not FileAccess.file_exists(marker_path):
		return false
	var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker_path))
	if not marker is Dictionary or marker.get("kind") != "tetris-isolated-test":
		return false
	var actual_root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var marked_root := str(marker.get("project_root", "")).replace("\\", "/").trim_suffix("/")
	var source_root := str(marker.get("source_root", "")).replace("\\", "/").trim_suffix("/")
	return actual_root == marked_root and actual_root != source_root


func _check(condition: bool, description: String) -> void:
	_checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		_failures += 1


func _write_env(content: String) -> bool:
	var file := FileAccess.open(ENV_PATH, FileAccess.WRITE)
	if file == null:
		_check(false, "temporary dotenv can be written")
		return false
	file.store_string(content)
	file.close()
	return true


func _run() -> void:
	var config := CONFIG.load_configuration()
	_check(config.api_key.is_empty(), "missing dotenv has no API key")
	_check(config.api_base_url.is_empty(), "missing dotenv has no service URL")
	_check(config.model.is_empty(), "missing dotenv has no model")
	_check(not config.is_configured(), "missing dotenv remains unconfigured")

	if not _write_env("AI_API_KEY=\nAI_API_BASE_URL=\nAI_MODEL=\n"):
		_finish()
		return
	config = CONFIG.load_configuration()
	_check(config.api_key.is_empty() and config.api_base_url.is_empty() and config.model.is_empty(), "empty assignments remain empty")
	_check(not config.is_configured(), "empty assignments remain unconfigured")

	if not _write_env("\ufeff# Test fixture; these values are fake.\n\n  # Ignore comment = entries.\nAI_API_KEY = 'fake=quoted-secret'\nAI_API_BASE_URL=\"https://example.invalid/v1?tenant=qa\"\nAI_MODEL='test=model'\nUNKNOWN_KEY=fake-unrecognized-value\nBROKEN_LINE\n"):
		_finish()
		return
	config = CONFIG.load_configuration()
	_check(config.api_key == "fake=quoted-secret", "single-quoted value preserves equals")
	_check(config.api_base_url == "https://example.invalid/v1?tenant=qa", "double-quoted URL preserves equals")
	_check(config.model == "test=model", "quoted model preserves equals")
	_check(config.is_configured(), "three configured values enable readiness")
	var parsed := CONFIG._read_project_env()
	_check(parsed.size() == 3, "blank lines and comments do not create keys")
	_check(not parsed.has("UNKNOWN_KEY"), "unknown keys are ignored")
	_check(not parsed.has("BROKEN_LINE"), "lines without assignment are ignored")

	if not _write_env(" AI_API_KEY = fake-file-key \n AI_API_BASE_URL = https://example.invalid/file \n AI_MODEL = fake-file-model \n"):
		_finish()
		return
	config = CONFIG.load_configuration()
	_check(config.api_key == "fake-file-key", "unquoted key trims surrounding whitespace")
	_check(config.api_base_url == "https://example.invalid/file", "unquoted URL trims surrounding whitespace")
	_check(config.model == "fake-file-model", "unquoted model trims surrounding whitespace")

	OS.set_environment("AI_API_KEY", "fake-process-key")
	OS.set_environment("AI_API_BASE_URL", "https://example.invalid/process")
	OS.set_environment("AI_MODEL", "fake-process-model")
	config = CONFIG.load_configuration()
	_check(config.api_key == "fake-process-key", "process API key overrides dotenv")
	_check(config.api_base_url == "https://example.invalid/process", "process URL overrides dotenv")
	_check(config.model == "fake-process-model", "process model overrides dotenv")
	_check(config.is_configured(), "complete process configuration is ready")

	OS.set_environment("AI_API_KEY", "")
	config = CONFIG.load_configuration()
	_check(OS.has_environment("AI_API_KEY"), "explicit empty process key remains present")
	_check(config.api_key.is_empty(), "explicit empty process key overrides dotenv")
	_check(not config.is_configured(), "explicit empty API key disables readiness")
	OS.set_environment("AI_API_BASE_URL", "")
	OS.set_environment("AI_MODEL", "")
	config = CONFIG.load_configuration()
	_check(config.api_base_url.is_empty() and config.model.is_empty(), "explicit empty process URL and model override dotenv")

	for key in KEYS:
		OS.unset_environment(key)
	config = CONFIG.load_configuration()
	_check(config.api_key == "fake-file-key" and config.api_base_url == "https://example.invalid/file" and config.model == "fake-file-model", "unset process values expose dotenv values again")
	_finish()


func _finish() -> void:
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(ENV_PATH))
	_check(remove_error == OK and not FileAccess.file_exists(ENV_PATH), "temporary dotenv removed")
	var restored := true
	for key in KEYS:
		var saved: Dictionary = _saved_environment[key]
		if bool(saved["present"]):
			OS.set_environment(key, str(saved["value"]))
		else:
			OS.unset_environment(key)
		restored = restored and OS.has_environment(key) == bool(saved["present"])
		restored = restored and OS.get_environment(key) == str(saved["value"])
	_saved_environment.clear()
	_check(restored, "original process environment restored without logging values")
	print("Assistant config regression: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
