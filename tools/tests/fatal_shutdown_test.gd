extends SceneTree

func _initialize() -> void:
	StorageBudget.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("fatal-data"))
	_run.call_deferred()

func _run() -> void:
	var diagnostics := root.get_node("Diagnostics")
	diagnostics.fatal_shutdown_requested.connect(func(): StorageBudget.write_atomic(StorageBudget.data_root().path_join("shutdown-observed.txt"), "shutdown signal before quit".to_utf8_buffer(), 1024, false))
	# Inject into the custom logger only; never provoke a real device failure.
	diagnostics._logger._log_message("0x887a0005", true)
