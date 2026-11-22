extends Node

var _failures := 0
var _checks := 0

func _ready() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1":
		get_tree().quit(2)
		return
	StorageBudget.configure_root_for_tests(OS.get_environment("TETRIS_RUN_DIR").path_join("data"))
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		_failures += 1

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	get_viewport().push_input(event)

func _joy(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	get_viewport().push_input(event)

func _check_result_lock(game: TetrisCore, rematch: Button, lobby: Button) -> void:
	await _settle()
	var activations := [0]
	rematch.pressed.connect(func(): activations[0] += 1)
	rematch.grab_focus()
	_key(KEY_RIGHT, true)
	_key(KEY_RIGHT, false)
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	_joy(JOY_BUTTON_B, true)
	_joy(JOY_BUTTON_B, false)
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = lobby.get_global_rect().get_center()
		click.pressed = pressed
		get_viewport().push_input(click, true)
	_check(rematch.has_focus() and activations[0] == 0 and not UITheme._changing_scene, game.name + " blocks navigation, confirmation, mouse and cancel before the GUI")
	await get_tree().create_timer(0.60).timeout
	_joy(JOY_BUTTON_A, true)
	_joy(JOY_BUTTON_A, false)
	_key(KEY_ENTER, true)
	_check(activations[0] == 0, game.name + " still guards the result after 0.6 seconds")
	await get_tree().create_timer(0.24).timeout
	_key(KEY_ENTER, true, true)
	_key(KEY_ENTER, false)
	_check(activations[0] == 0, game.name + " ignores a held confirmation crossing the unlock boundary")
	_joy(JOY_BUTTON_A, true)
	_joy(JOY_BUTTON_A, false)
	_check(activations[0] == 1, game.name + " accepts a fresh gamepad confirmation after 0.8 seconds")

func _run() -> void:
	var single: GameScene = load("res://scenes/game.tscn").instantiate()
	add_child(single)
	single.set_process(false)
	single._on_game_over()
	for locale in ["en", "ja", "zh"]:
		TranslationServer.set_locale(locale)
		await _settle()
		_check(single.label_game_over.text == tr("TXT_GAME_OVER"), "Single-player result title follows " + locale)
		_check(single.btn_restart.text == tr("TXT_RESTART") and single.btn_return.text == tr("TXT_RETURN_LOBBY"), "Single-player result buttons follow " + locale)
		_check(single.label_game_over.get_global_rect().end.y + 10.0 < single.btn_restart.get_global_rect().position.y, "Result title is above the restart button in " + locale)
	_check(single.game_over_panel.is_ancestor_of(single.label_game_over), "Result title belongs to the native overlay")
	single.free()
	await _settle()
	var versus: Node = load("res://scenes/multiplayer_game.tscn").instantiate()
	add_child(versus)
	versus.set_process(false)
	TranslationServer.set_locale("en")
	await _settle()
	var status_rect: Rect2 = versus.label_status.get_global_rect()
	_check(versus.label_status.get_line_count() >= 2, "English battle status wraps")
	_check(status_rect.position.x >= 650 and status_rect.end.x < 800, "Battle status stays between the next panel and opponent board")
	versus._on_opponent_game_over()
	await _check_result_lock(versus, versus.game_over_panel.btn_rematch, versus.game_over_panel.btn_lobby)
	versus.free()
	await _settle()
	var royale: Tetris33Game = load("res://scenes/tetris33_game.tscn").instantiate()
	add_child(royale)
	royale.set_process(false)
	_joy(JOY_BUTTON_B, true)
	_joy(JOY_BUTTON_B, false)
	_check(not UITheme._changing_scene, "Tetris33 lets the gamepad B hard drop finish during play")
	royale._on_local_game_over()
	_joy(JOY_BUTTON_B, true)
	_joy(JOY_BUTTON_B, false)
	_check(not UITheme._changing_scene, "Tetris33 guards cancel when elimination switches to spectating")
	royale._local_rank = 1
	royale._match_finished = true
	royale._refresh_match_labels()
	royale._show_rank_result(true)
	# 离线重开会重载整个测试场景，这里只记录原生按钮是否被激活。
	royale.btn_restart.pressed.disconnect(royale._on_rematch_pressed)
	await _check_result_lock(royale, royale.btn_restart, royale.btn_lobby)
	royale._log_attack("TXT_TETRIS33_INCOMING", [3])
	for locale in ["en", "ja", "zh"]:
		TranslationServer.set_locale(locale)
		await _settle()
		_check(royale.btn_restart.text == tr("TXT_RESTART") and royale.btn_lobby.text == tr("TXT_RETURN_LOBBY"), "Tetris33 result buttons follow " + locale)
		_check(royale.label_status.text == tr("TXT_TETRIS33_FINISHED"), "Tetris33 match state follows " + locale)
		_check(royale.result_label.text == tr("TXT_TETRIS33_WINNER") + "\n" + tr("TXT_TETRIS33_REMATCH_READY"), "Tetris33 result title and subtitle follow " + locale)
		_check(royale.label_attack_log.text == tr("TXT_TETRIS33_INCOMING") % 3, "Attack state survives language change to " + locale)
	royale._set_result_subtitle("TXT_TETRIS33_REMATCH_WAITING", [2, 5])
	TranslationServer.set_locale("en")
	await _settle()
	_check(royale.result_label.text.ends_with(tr("TXT_TETRIS33_REMATCH_WAITING") % [2, 5]), "Rematch vote counts survive language change")
	royale._rematch_requested = true
	TranslationServer.set_locale("ja")
	await _settle()
	_check(royale.btn_restart.text == tr("TXT_WAITING_CONNECT"), "Requested rematch keeps its waiting state after language change")
	_check(royale.local_ko_name_label.get_theme_color("font_color").get_luminance() > 0.8, "Eliminated-player rank stays bright over the dark board")
	royale.free()
	ButtonSfx.get_node("ButtonClickPlayer").stop()
	await get_tree().create_timer(0.5).timeout
	print("GAME_UI_REGRESSION checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
