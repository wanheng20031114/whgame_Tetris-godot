class_name MlpEnvironment
extends RefCounted

const MLP_DIR_NAME: String = "MLP"
const SETUP_SCRIPT_NAME: String = "setup_env.bat"
const PYTHON_IMPORT_CHECK: String = "import torch, numpy"

static var _background_setup_started: bool = false


static func get_mlp_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://%s" % MLP_DIR_NAME)
	return OS.get_executable_path().get_base_dir().path_join(MLP_DIR_NAME)


static func find_python(mlp_dir: String = "") -> String:
	var root: String = mlp_dir if not mlp_dir.is_empty() else get_mlp_dir()

	var venv_python: String = root.path_join(".venv/Scripts/python.exe")
	if FileAccess.file_exists(venv_python):
		return venv_python

	var venv_python_unix: String = root.path_join(".venv/bin/python")
	if FileAccess.file_exists(venv_python_unix):
		return venv_python_unix

	var output: Array = []
	if OS.execute("python", ["--version"], output, true) == 0:
		return "python"
	if OS.execute("python3", ["--version"], output, true) == 0:
		return "python3"

	return ""


static func ensure_environment(show_setup_window: bool = true) -> bool:
	var mlp_dir: String = get_mlp_dir()
	if not DirAccess.dir_exists_absolute(mlp_dir):
		push_warning("[MlpEnvironment] MLP directory is missing: %s" % mlp_dir)
		return false

	if _venv_dependencies_ready(mlp_dir):
		return true

	var setup_path: String = mlp_dir.path_join(SETUP_SCRIPT_NAME)
	if not FileAccess.file_exists(setup_path):
		push_warning("[MlpEnvironment] Setup script is missing: %s" % setup_path)
		return false

	var exit_code: int = _run_setup_script(setup_path, show_setup_window)
	if exit_code != 0:
		push_warning("[MlpEnvironment] Setup script failed with exit code %d" % exit_code)
		return false

	return _venv_dependencies_ready(mlp_dir)


static func start_environment_setup_background(show_setup_window: bool = true) -> bool:
	var mlp_dir: String = get_mlp_dir()
	if not DirAccess.dir_exists_absolute(mlp_dir):
		push_warning("[MlpEnvironment] MLP directory is missing: %s" % mlp_dir)
		return false

	if _background_setup_started:
		return true

	if _venv_dependency_files_present(mlp_dir):
		return true

	var setup_path: String = mlp_dir.path_join(SETUP_SCRIPT_NAME)
	if not FileAccess.file_exists(setup_path):
		push_warning("[MlpEnvironment] Setup script is missing: %s" % setup_path)
		return false

	var pid: int = _start_setup_script_background(setup_path, show_setup_window)
	if pid <= 0:
		push_warning("[MlpEnvironment] Failed to start setup script in background")
		return false

	_background_setup_started = true
	print("[MlpEnvironment] Started setup script in background, pid=%d" % pid)
	return true


static func _venv_dependencies_ready(mlp_dir: String) -> bool:
	var venv_python: String = mlp_dir.path_join(".venv/Scripts/python.exe")
	if not FileAccess.file_exists(venv_python):
		venv_python = mlp_dir.path_join(".venv/bin/python")
	if not FileAccess.file_exists(venv_python):
		return false

	var output: Array = []
	return OS.execute(venv_python, ["-c", PYTHON_IMPORT_CHECK], output, true) == 0


static func _venv_dependency_files_present(mlp_dir: String) -> bool:
	var venv_python: String = mlp_dir.path_join(".venv/Scripts/python.exe")
	var site_packages: String = mlp_dir.path_join(".venv/Lib/site-packages")
	if not FileAccess.file_exists(venv_python):
		venv_python = mlp_dir.path_join(".venv/bin/python")
		site_packages = mlp_dir.path_join(".venv/lib")

	if not FileAccess.file_exists(venv_python):
		return false

	if OS.get_name() == "Windows":
		return (
			DirAccess.dir_exists_absolute(site_packages.path_join("torch"))
			and DirAccess.dir_exists_absolute(site_packages.path_join("numpy"))
		)

	return _venv_dependencies_ready(mlp_dir)


static func _run_setup_script(setup_path: String, show_setup_window: bool) -> int:
	if OS.get_name() == "Windows":
		if show_setup_window:
			var start_command: String = "start \"\" /wait %s" % _cmd_quote(setup_path)
			var start_exit_code: int = OS.execute("cmd.exe", ["/d", "/c", start_command], [], true)
			if start_exit_code == 0:
				return 0

		var call_command: String = "call %s" % _cmd_quote(setup_path)
		return OS.execute("cmd.exe", ["/d", "/c", call_command], [], true)

	return OS.execute(setup_path, [], [], true)


static func _start_setup_script_background(setup_path: String, show_setup_window: bool) -> int:
	if OS.get_name() == "Windows":
		if show_setup_window:
			var start_command: String = "start \"\" %s" % _cmd_quote(setup_path)
			return OS.create_process("cmd.exe", ["/d", "/c", start_command], false)

		var call_command: String = "call %s" % _cmd_quote(setup_path)
		return OS.create_process("cmd.exe", ["/d", "/c", call_command], false)

	return OS.create_process(setup_path, [], false)


static func _cmd_quote(path: String) -> String:
	return "\"%s\"" % path.replace("\"", "\"\"")
