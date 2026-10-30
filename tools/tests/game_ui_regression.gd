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
	versus.free()
	await _settle()
	var royale: Tetris33Game = load("res://scenes/tetris33_game.tscn").instantiate()
	add_child(royale)
	royale.set_process(false)
	royale._local_rank = 1
	royale._match_finished = true
	royale._refresh_match_labels()
	royale._show_rank_result(true)
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
	await get_tree().create_timer(0.2).timeout
	print("GAME_UI_REGRESSION checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
