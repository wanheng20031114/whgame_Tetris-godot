extends Node
## Lifecycle, timing and stable wrapping through the real native assistant scene.

@onready var panel: AyaoAssistantPanel = $Assistant
@onready var writer: DialogueTypewriter = panel.typewriter
@onready var voice: AudioStreamPlayer = writer.blip_audio
var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1" or not FileAccess.file_exists("res://.safe-run-isolated.json"):
		get_tree().quit(2)
		return
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		print("FAIL " + description)


func _settle() -> void:
	for frame in 4:
		await get_tree().process_frame


func _review() -> Dictionary:
	return {"kind": "tip", "title_key": "TXT_AYAO_WELCOME_TITLE", "body_key": "TXT_AYAO_WELCOME_BODY",
		"body_args": [], "advice_key": "TXT_AYAO_WELCOME_ADVICE", "advice_args": []}


func _test_cadence() -> void:
	panel.body_label.text = "甲，乙。丙"
	panel.advice_label.text = "建议"
	writer.play()
	_check(panel.body_label.visible_characters == 0 and panel.advice_label.visible_characters == 0, "both paragraphs start hidden")
	writer._process(0.0)
	_check(panel.body_label.visible_characters == 1 and voice.playing, "first character plays its blip")
	voice.stop()
	writer._process(0.035)
	_check(panel.body_label.visible_characters == 2 and not voice.playing, "comma is silent")
	writer._process(0.119)
	_check(panel.body_label.visible_characters == 2, "comma pauses for 120 ms")
	writer._process(0.0011)
	_check(panel.body_label.visible_characters == 3 and voice.playing, "letters resume after comma")
	voice.stop()
	writer._process(0.035)
	_check(panel.body_label.visible_characters == 4 and not voice.playing, "sentence ending is silent")
	writer._process(0.219)
	_check(panel.body_label.visible_characters == 4, "sentence ending pauses for 220 ms")
	writer._process(0.0011)
	_check(panel.body_label.visible_characters == 5 and panel.advice_label.visible_characters == 0, "observation completes before advice")
	writer._process(0.219)
	_check(panel.advice_label.visible_characters == 0, "paragraph transition has a pause")
	writer._process(0.0011)
	_check(panel.advice_label.visible_characters == 1, "advice starts after observation")
	writer._process(0.035)
	writer._process(0.035)
	_check(not writer.is_revealing() and panel.advice_label.visible_characters == -1 and not voice.playing, "completion stops processing and audio")
	panel.body_label.text = "甲乙丙丁"
	writer.play()
	writer._process(2.0)
	_check(panel.body_label.visible_characters == 1, "a stalled frame never bursts through multiple characters")
	writer.finish()
	for text in ["", " ，。！？：；…\n ", "Word, next.", "こんにちは。"]:
		panel.body_label.text = text
		panel.advice_label.text = ""
		writer.play()
		for i in text.length() + 2:
			writer._process(0.25)
		_check(not writer.is_revealing(), "empty, punctuation and localized lines terminate: " + text)
	writer.finish()


func _test_lifecycle() -> void:
	panel.present_review(0, 4, _review(), true)
	writer._process(0.0)
	var count := panel.body_label.visible_characters
	panel.set_plan_preview(true)
	panel.present_review(0, 4, _review(), true)
	UITheme.set_mode("light", Vector2(-1, -1), false)
	_check(writer.is_revealing() and panel.body_label.visible_characters == count, "metadata, same-step and theme refresh preserve progress")
	panel.present_review(1, 4, _review(), true)
	_check(panel.body_label.visible_characters == 0 and not voice.playing, "new step cancels old audio and restarts text")
	writer._process(0.0)
	panel.toggle_button.pressed.emit()
	_check(not writer.is_revealing() and not voice.playing, "collapse immediately stops speech")
	panel.present_review(2, 4, _review(), true)
	_check(not writer.is_revealing() and panel._current_step == 2, "hidden review updates without speech")
	panel.toggle_button.pressed.emit()
	_check(panel.body_label.visible_characters == -1 and not writer.is_revealing(), "expansion shows latest complete review")
	panel.present_review(3, 4, _review(), true)
	writer._process(0.0)
	panel.hide()
	_check(not writer.is_revealing() and not voice.playing, "hidden panel stops speech")
	panel.show()
	_check(not writer.is_revealing(), "showing panel does not replay old speech")
	panel.present_review(0, 4, _review(), true)
	writer._process(0.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel._gui_input(click)
	_check(not writer.is_revealing() and not voice.playing and panel.advice_label.visible_characters == -1, "click reveals both paragraphs immediately and silently")
	panel.present_review(1, 4, _review(), true)
	writer._process(0.0)
	TranslationServer.set_locale("en")
	_check(not writer.is_revealing() and not voice.playing and not panel.body_label.text.contains("TXT_"), "language change cancels old speech and keeps translation")
	panel.present_review(2, 4, _review(), true)
	writer._process(0.0)
	panel.clear_review()
	_check(not writer.is_revealing() and not voice.playing and panel._current_step == -1, "session clear cancels speech and shows welcome")
	var master := AudioServer.get_bus_index("Master")
	var was_muted := AudioServer.is_bus_mute(master)
	AudioServer.set_bus_mute(master, true)
	panel.present_review(0, 4, _review(), false)
	writer._process(0.0)
	_check(AudioServer.is_bus_mute(master) and voice.bus == &"Master", "speech obeys existing Master mute without overriding it")
	writer.finish()
	AudioServer.set_bus_mute(master, was_muted)
	var randomizer := voice.stream as AudioStreamRandomizer
	_check(randomizer != null and randomizer.random_pitch > 1.0 and randomizer.random_volume_offset_db > 0.0, "native audio randomizer varies pitch and volume")
	_check(randomizer.get_stream(0).resource_path == "res://audio/ayao_dialogue_blip.wav", "voice uses the arc-nice original sound")


func _test_layout() -> void:
	for locale in ["zh", "en", "ja"]:
		TranslationServer.set_locale(locale)
		panel.present_review(0, 4, _review(), true)
		writer.finish()
		await _settle()
		var body_rect := panel.body_label.get_global_rect()
		var advice_rect := panel.advice_card.get_global_rect()
		var panel_rect := panel.get_global_rect()
		writer.play()
		await _settle()
		_check(panel.body_label.get_global_rect() == body_rect and panel.advice_card.get_global_rect() == advice_rect and panel.get_global_rect() == panel_rect,
			locale + ": full layout stays fixed when only first characters are shown")
		writer.finish()


func _run() -> void:
	var original_locale := TranslationServer.get_locale()
	var original_theme := UITheme.mode
	TranslationServer.set_locale("zh")
	await _settle()
	_test_cadence()
	_test_lifecycle()
	await _test_layout()
	panel.present_review(1, 4, _review(), false)
	writer._process(0.0)
	panel.queue_free()
	await _settle()
	_check(not is_instance_valid(voice), "leaving scene releases the audio player")
	TranslationServer.set_locale(original_locale)
	UITheme.set_mode(original_theme, Vector2(-1, -1), false)
	await get_tree().create_timer(0.5).timeout
	print(JSON.stringify({"test": "ayao_typewriter_regression", "checks": _checks, "failures": _failures, "ok": _failures.is_empty()}))
	get_tree().quit(0 if _failures.is_empty() else 1)
