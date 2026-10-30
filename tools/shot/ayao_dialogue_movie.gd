extends "res://tools/shot/ayao_replay.gd"
## Actual replay UI and audio, captured with Godot's --write-movie option.


func _run() -> void:
	var replay = instantiate_scene("res://scenes/ui/replay_system.tscn")
	replay._load_session(_fixture())
	replay.session_list_popup.hide()
	TranslationServer.set_locale("zh")
	var ui := root.get_node("UITheme")
	ui.set_mode("dark", Vector2(-1, -1), false)
	ui._on_scene_changed()
	replay.assistant_panel.typewriter.finish()
	await create_timer(0.5).timeout
	replay.btn_next.pressed.emit()
	await create_timer(0.38).timeout
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("TETRIS_RUN_DIR")
	if not save_screenshot(output.path_join("praise-typing.png")):
		return
	await create_timer(3.22).timeout
	await RenderingServer.frame_post_draw
	if not save_screenshot(output.path_join("praise-complete.png")):
		return
	replay.btn_next.pressed.emit()
	await create_timer(0.65).timeout
	await RenderingServer.frame_post_draw
	if not save_screenshot(output.path_join("tip-typing.png")):
		return
	await create_timer(3.55).timeout
	replay.btn_next.pressed.emit()
	await create_timer(3.5).timeout
	# Exercise fast scrubbing and an actual GUI click to finish the current line.
	replay._go_to_step(1)
	await create_timer(0.45).timeout
	replay._go_to_step(2)
	await create_timer(0.45).timeout
	var click := InputEventMouseButton.new()
	click.position = replay.assistant_panel.body_label.get_global_rect().get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	var release := click.duplicate() as InputEventMouseButton
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	if replay.assistant_panel.typewriter.is_revealing():
		fail("Clicking the actual dialogue did not finish its reveal")
		return
	await create_timer(0.5).timeout
	replay.assistant_panel.toggle_button.pressed.emit()
	await create_timer(0.6).timeout
	replay.assistant_panel.toggle_button.pressed.emit()
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	if not save_screenshot(output.path_join("screen.png")):
		return
	print("AYAO_DIALOGUE_MOVIE_OK ", replay.assistant_panel.get_global_rect())
	replay.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(0)
