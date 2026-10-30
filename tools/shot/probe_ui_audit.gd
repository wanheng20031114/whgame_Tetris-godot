extends "res://tools/shot/shot_support.gd"
## Isolated UI regression checks. Run only via tools/safe_run.py.

var _failures: Array[String] = []
var _login_count := 0
var _check_count := 0


func _start() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append(message)


func _dispose(scene: Node) -> void:
	# Let scene-ready/deferred focus and layout callbacks finish before detaching.
	await process_frame
	root.remove_child(scene)
	scene.queue_free()
	await process_frame


func _run() -> void:
	var theme := root.get_node("UITheme")
	var logical_size := root.content_scale_size
	var settings := instantiate_scene("res://scenes/ui/settings_menu.tscn")
	await process_frame
	_expect(root.content_scale_size == logical_size, "Opening a settings instance changed logical resolution")
	settings.show_menu()
	await process_frame
	_expect(settings.is_menu_open(), "Settings did not open")
	_expect(settings._action_slot_buttons.size() == 9, "Settings lost binding rows")
	_expect(settings._handling_sliders.size() == 4, "Settings lost handling sliders")
	var physical_default := InputEventKey.new()
	physical_default.physical_keycode = KEY_A
	var pressed := InputEventKey.new()
	pressed.physical_keycode = KEY_A
	pressed.keycode = KEY_A
	pressed.pressed = true
	var captured: InputEventKey = settings._extract_binding_event(pressed)
	_expect(settings._events_equal(physical_default, captured), "Physical default duplicate was not recognized")
	pressed.ctrl_pressed = true
	captured = settings._extract_binding_event(pressed)
	_expect(settings._event_to_display_text(captured).contains("Ctrl"), "Binding label omitted Ctrl")
	var toggle: Button = settings.fullscreen_checkbox
	var unrelated := theme.create_tween().set_loops()
	unrelated.tween_interval(1.0)
	toggle.set_pressed_no_signal(not toggle.button_pressed)
	await process_frame
	await process_frame
	_expect(is_equal_approx(toggle._k, 1.0 if toggle.button_pressed else 0.0), "Unrelated Tween blocked toggle synchronization")
	unrelated.kill()
	settings.hide_menu()
	await _dispose(settings)

	var lobby := instantiate_scene("res://scenes/ui/main_lobby.tscn")
	await process_frame
	var marathon: Control = lobby.get_node("%CardMarathon")
	var guide: Control = lobby.get_node("%CardGuide")
	var multiplayer: Control = lobby.get_node("%CardMultiplayer")
	var replay: Control = lobby.get_node("%CardReplay")
	_expect(marathon.get_node(marathon.focus_neighbor_bottom) == multiplayer, "First column Down skips row 2")
	_expect(guide.get_node(guide.focus_neighbor_bottom) == replay, "Second column Down skips row 2")
	_expect(multiplayer.get_node(multiplayer.focus_neighbor_right) == replay, "Second row Right is wrong")
	var first_motion: Tween = theme.motion_tween(marathon)
	first_motion.tween_property(marathon, "scale", Vector2(1.1, 1.1), 1.0)
	var next_motion: Tween = theme.motion_tween(marathon)
	next_motion.tween_property(marathon, "scale", Vector2.ONE, 0.1)
	_expect(not first_motion.is_valid(), "Conflicting motion Tween survived replacement")
	var style := lobby.get_node("%BtnBlockStyle")
	style._open_menu()
	lobby.get_node("%BtnStats").grab_focus()
	_expect(style._panel.is_ancestor_of(root.gui_get_focus_owner()), "Modal focus escaped to the obscured lobby")
	theme.set_mode("light", Vector2(-1, -1), false)
	var current: String = root.get_node("BlockStyleManager").get_current_style_id()
	var selected: Button = style._style_buttons[current]
	var expected_color: Color = theme.color("surface").lerp(theme.color("accent"), 0.16)
	_expect(selected.get_theme_stylebox("normal").bg_color.is_equal_approx(expected_color), "Style card did not follow theme")
	_expect(selected.get_theme_stylebox("hover_pressed").bg_color.is_equal_approx(expected_color), "Selected hover card lost selection color")
	for id in style._style_buttons:
		_expect(style._style_buttons[id].get_node("Margin/Row/Preview").style_id == id, "Style preview does not match its card")
	style._close_menu()
	await _dispose(lobby)

	var login := instantiate_scene("res://scenes/ui/login_screen.tscn")
	login.login_successful.connect(func(_name): _login_count += 1)
	login._submit_login()
	login._submit_login()
	await create_timer(0.35).timeout
	_expect(_login_count == 1, "Repeated submit emitted more than one login")
	await _dispose(login)

	var result := instantiate_scene("res://scenes/ui/game_over_panel.tscn")
	result.show_result("TXT_OPPONENT_LEFT_TITLE", "TEST")
	await process_frame
	_expect(result.btn_rematch.disabled, "Rematch enabled after opponent left")
	_expect(result.btn_lobby.has_focus(), "Unavailable rematch kept keyboard focus")
	await _dispose(result)

	var setup := instantiate_scene("res://scenes/ui/multiplayer_setup.tscn")
	setup._is_connecting = true
	setup._pending_name = "TEST"
	setup._on_network_connected()
	_expect(setup._is_connecting, "Login handshake escaped connection timeout")
	setup._set_status_key("TXT_CONNECTION_FAILED_REASON", ["test"], true)
	TranslationServer.set_locale("en")
	_expect(setup.lbl_status.text.begins_with("Connection failed"), "Connection error did not follow language")
	await _dispose(setup)

	var opponent := instantiate_scene("res://scenes/ui/tetris33_opponent_panel.tscn")
	var full_name := "测试玩家十二字名称完整显示"
	opponent.update_from_sample({"name": full_name})
	await process_frame
	_expect(opponent.name_label.clip_text and opponent.name_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "Opponent name is not clipped with ellipsis")
	_expect(opponent.name_label.size.x <= 76.0, "Long opponent name widened the mini-board")
	_expect(opponent.name_label.tooltip_text == full_name, "Opponent name tooltip lost the full name")
	await _dispose(opponent)

	if not _failures.is_empty():
		fail("UI regression failures: " + "; ".join(_failures))
		return
	print("UI audit regression: %d checks passed" % _check_count)
	quit(0)
