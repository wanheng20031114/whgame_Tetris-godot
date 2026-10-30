extends SceneTree

func _initialize() -> void:
	var data := OS.get_environment("TETRIS_RUN_DIR").path_join("concurrent-data")
	if StorageBudget.configure_root_for_tests(data, 20000) != OK:
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	root.get_node("Diagnostics").set_process(false)
	var written := 0
	var data := StorageBudget.data_root()
	var bytes := "x".repeat(1000).to_utf8_buffer()
	for index in range(40):
		var path := data.path_join("%d-%d.bin" % [OS.get_process_id(), index])
		if StorageBudget.write_atomic(path, bytes, 1000, false) == OK:
			written += 1
		OS.delay_msec(2)
	print(JSON.stringify({"written": written}))
	quit()
