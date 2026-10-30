extends SceneTree

func _initialize() -> void:
	StorageBudget.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("ui-data"))
	_run.call_deferred()

func _run() -> void:
	for path in ["res://scenes/ui/replay_system.tscn", "res://scenes/ui/multiplayer_lobby.tscn"]:
		var scene: Node = load(path).instantiate()
		root.add_child(scene)
		await process_frame
		scene.free()
	print("UI_SMOKE_OK replay and multiplayer lobby")
	quit()
