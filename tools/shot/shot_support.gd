extends SceneTree
## Shared test lifecycle. The external Job Object remains the hard timeout.

const INTERNAL_TIMEOUT_SECONDS := 20.0


func _initialize() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1":
		fail("Use tools/safe_run.py with an isolated project", 2)
		return
	if bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging", true)):
		fail("Engine file logging must be disabled in the isolated project", 2)
		return
	create_timer(INTERNAL_TIMEOUT_SECONDS).timeout.connect(func(): fail("Internal test deadline exceeded", 124))
	_start.call_deferred()


func _start() -> void:
	fail("Test entry point is not implemented")


func fail(message: String, exit_code: int = 1) -> void:
	printerr("TEST FAILURE: ", message)
	quit(exit_code)


func instantiate_scene(scene_path: String) -> Node:
	if not scene_path.begins_with("res://") or not ResourceLoader.exists(scene_path, "PackedScene"):
		fail("Missing scene: " + scene_path)
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		fail("Not a PackedScene: " + scene_path)
		return null
	var instance := packed.instantiate()
	if instance == null:
		fail("Cannot instantiate: " + scene_path)
		return null
	root.add_child(instance)
	current_scene = instance
	return instance


func save_screenshot(path: String) -> bool:
	var run_dir := OS.get_environment("TETRIS_RUN_DIR").replace("\\", "/").simplify_path()
	var absolute := ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()
	if run_dir.is_empty() or not absolute.begins_with(run_dir + "/"):
		fail("Screenshot path must be inside this supervised run directory")
		return false
	if FileAccess.file_exists(absolute):
		fail("Refusing to overwrite an existing screenshot: " + absolute)
		return false
	if DisplayServer.get_name() == "headless":
		fail("Screenshots require a rendered viewport")
		return false
	var texture := root.get_texture()
	if texture == null:
		fail("Viewport texture is unavailable")
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		fail("Viewport image is unavailable")
		return false
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		fail("Cannot create screenshot directory: " + error_string(directory_error))
		return false
	var save_error := image.save_png(absolute)
	if save_error != OK:
		fail("Cannot save screenshot: " + error_string(save_error))
		return false
	var verified := Image.new()
	var load_error := verified.load(absolute)
	if load_error != OK or verified.is_empty() or verified.get_size() != image.get_size():
		fail("Saved screenshot failed read-back validation")
		return false
	print("SHOT ", absolute, " ", image.get_size())
	return true
