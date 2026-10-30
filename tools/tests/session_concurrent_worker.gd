extends SceneTree

func _initialize() -> void:
	var data := OS.get_environment("TETRIS_RUN_DIR").path_join("concurrent-sessions")
	if StorageBudget.configure_root_for_tests(data, 20000, 6000) != OK:
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	root.get_node("Diagnostics").set_process(false)
	var written := 0
	var bytes := "x".repeat(1000).to_utf8_buffer()
	for index in range(25):
		var path := StorageBudget.data_root().path_join("sessions/session_shared.json.tmp.%d-%d" % [OS.get_process_id(), index])
		if StorageBudget.write_atomic(path, bytes, 1000, false) == OK:
			written += 1
		OS.delay_msec(3)
	print(JSON.stringify({"written": written}))
	quit()
