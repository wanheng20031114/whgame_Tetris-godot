extends "res://tools/shot/shot_support.gd"
## 每个界面加载后来回切换主题，检查运行时报错
const SCENES := ["res://scenes/ui/main.tscn", "res://scenes/ui/main_lobby.tscn", "res://scenes/ui/guide_system.tscn",
	"res://scenes/ui/replay_system.tscn", "res://scenes/ui/player_stats_screen.tscn", "res://scenes/ui/multiplayer_setup.tscn",
	"res://scenes/ui/multiplayer_lobby.tscn", "res://scenes/ui/settings_menu.tscn", "res://scenes/ui/block_style_menu.tscn",
	"res://scenes/game.tscn"]
func _start() -> void:
	_go.call_deferred()
func _go():
	var ui = root.get_node_or_null("UITheme")
	if ui == null:
		fail("UITheme is unavailable")
		return
	for path in SCENES:
		var inst := instantiate_scene(path)
		if inst == null:
			return
		for i in 3: await process_frame
		if inst.has_method("show_menu"): inst.show_menu()
		if inst.has_method("_toggle_menu"): inst._toggle_menu()
		for m in ["light", "dark", "light", "dark"]:
			ui.set_mode(m, Vector2(-1, -1), false)
			for i in 2: await process_frame
		print("OK ", path)
		inst.queue_free()
		await process_frame
	quit(0)
