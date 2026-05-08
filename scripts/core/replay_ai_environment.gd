class_name ReplayAiEnvironment
extends RefCounted

const WINDOWS_ANALYZER_RESOURCE: String = "res://replay-ai-core/bin/windows/analyze_session.exe"
const WINDOWS_ANALYZER_CACHE_DIR: String = "user://replay-ai-core/bin/windows"
const WINDOWS_ANALYZER_NAME: String = "analyze_session.exe"


static func ensure_analyzer_available() -> String:
	if OS.get_name() == "Windows" and not OS.has_feature("editor"):
		var exe_analyzer_path: String = OS.get_executable_path().get_base_dir().path_join(WINDOWS_ANALYZER_NAME)
		if FileAccess.file_exists(exe_analyzer_path):
			return exe_analyzer_path
		var copied_path: String = _copy_windows_analyzer_to_exe_dir()
		if not copied_path.is_empty():
			return copied_path

	var analyzer_path: String = find_analyzer()
	if not analyzer_path.is_empty():
		return analyzer_path

	if OS.get_name() == "Windows":
		return _extract_windows_analyzer()

	return ""


static func find_analyzer() -> String:
	var candidates: Array[String] = []

	if OS.get_name() == "Windows":
		var exe_dir: String = OS.get_executable_path().get_base_dir()
		candidates.append(exe_dir.path_join(WINDOWS_ANALYZER_NAME))
		candidates.append(exe_dir.path_join("bin/windows/analyze_session.exe"))
		candidates.append(exe_dir.path_join("replay-ai-core/bin/windows/analyze_session.exe"))
		candidates.append(ProjectSettings.globalize_path(WINDOWS_ANALYZER_CACHE_DIR.path_join(WINDOWS_ANALYZER_NAME)))
		candidates.append(ProjectSettings.globalize_path("res://replay-ai-core/target/release/analyze_session.exe"))
		candidates.append(ProjectSettings.globalize_path("res://replay-ai-core/target/debug/analyze_session.exe"))
		if OS.has_feature("editor"):
			candidates.append(ProjectSettings.globalize_path(WINDOWS_ANALYZER_RESOURCE))
	else:
		candidates.append(ProjectSettings.globalize_path("res://replay-ai-core/target/release/analyze_session"))
		candidates.append(ProjectSettings.globalize_path("res://replay-ai-core/target/debug/analyze_session"))

	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


static func _extract_windows_analyzer() -> String:
	return _copy_windows_analyzer_to_dir(ProjectSettings.globalize_path(WINDOWS_ANALYZER_CACHE_DIR))


static func _copy_windows_analyzer_to_exe_dir() -> String:
	return _copy_windows_analyzer_to_dir(OS.get_executable_path().get_base_dir())


static func _copy_windows_analyzer_to_dir(target_dir: String) -> String:
	if not FileAccess.file_exists(WINDOWS_ANALYZER_RESOURCE):
		return ""

	var source := FileAccess.open(WINDOWS_ANALYZER_RESOURCE, FileAccess.READ)
	if source == null:
		return ""

	var err: int = DirAccess.make_dir_recursive_absolute(target_dir)
	if err != OK:
		push_warning("[ReplayAiEnvironment] Failed to create analyzer cache directory: %s" % target_dir)
		return ""

	var target_path: String = target_dir.path_join(WINDOWS_ANALYZER_NAME)
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		push_warning("[ReplayAiEnvironment] Failed to write analyzer cache: %s" % target_path)
		return ""

	target.store_buffer(source.get_buffer(source.get_length()))
	return target_path
