extends "res://tools/shot/shot_support.gd"
## 截图工具：godot --path . -s res://tools/shot/shot.gd -- <scene> <dark|light> <out.png> [frames]

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		fail("Usage: <scene> <dark|light> <out.png> [frames] [call_spec]", 2)
		return
	var scene_path: String = args[0]
	var theme_mode: String = args[1]
	var out: String = args[2]
	var frames: int = int(args[3]) if args.size() > 3 else 150
	var call_spec: String = args[4] if args.size() > 4 else ""
	if theme_mode not in ["dark", "light"] or frames < 0 or frames > 600:
		fail("Theme must be dark/light and frames must be in 0..600", 2)
		return
	if args.size() > 3 and not args[3].is_valid_int():
		fail("Frame count must be an integer", 2)
		return
	_run.call_deferred(scene_path, theme_mode, out, frames, call_spec)


## call_spec: "method" 或 "节点路径:method[:参数]"，在场景就绪后调用（用于打开弹层）
func _run(scene_path: String, theme_mode: String, out: String, frames: int, call_spec: String) -> void:
	var ui = root.get_node_or_null("UITheme")
	if ui:
		ui.mode = theme_mode
		ui._apply_theme()
	var inst := instantiate_scene(scene_path)
	if inst == null:
		return
	if ui:
		ui._on_scene_changed()
	for i in 5:
		await process_frame
	if not call_spec.is_empty():
		var parts := call_spec.split(":")
		var target: Node = inst
		var method := parts[0]
		if parts.size() >= 2:
			target = inst.get_node_or_null(parts[0]) if parts[0] != "." else inst
			method = parts[1]
		if target == null or not target.has_method(method):
			fail("Invalid call_spec target or method: " + call_spec, 2)
			return
		target.callv(method, Array(parts.slice(2)))
	for i in frames:
		await process_frame
	if DisplayServer.get_name() == "headless":
		fail("Screenshots cannot run headless")
		return
	await RenderingServer.frame_post_draw
	if save_screenshot(out):
		quit(0)
