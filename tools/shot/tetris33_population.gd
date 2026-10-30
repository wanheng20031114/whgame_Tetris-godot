extends "res://tools/shot/shot_support.gd"
## safe_run.py ... --resolution 1280x720 -s res://tools/shot/tetris33_population.gd -- 3 dark


func _initialize() -> void:
	super._initialize()
	var store = load("res://scripts/core/storage_budget.gd")
	store.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("data"))


func _start() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var player_count := int(args[0])
	var theme_name := args[1]
	var game = load("res://scenes/tetris33_game.tscn").instantiate()
	game.active_player_count = player_count
	root.add_child(game)
	current_scene = game
	game.bgm.stop()
	game.set_process(false)
	game.set_physics_process(false)
	TranslationServer.set_locale("zh")
	var ui := root.get_node("UITheme")
	ui.set_mode(theme_name, Vector2(-1, -1), false)
	ui._on_scene_changed()
	await create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("TETRIS_RUN_DIR")
	if not save_screenshot(output.path_join("screen.png")):
		return
	if args.size() > 2 and args[2] == "motion":
		game._send_attack_to_target(4)
		game._receive_attack(2)
		for frame in 36:
			await create_timer(0.05).timeout
			await RenderingServer.frame_post_draw
			if not save_screenshot(output.path_join("motion-%02d.png" % frame)):
				return
	print("POPULATION_SCREEN_OK ", player_count, " ", theme_name)
	game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(0)
