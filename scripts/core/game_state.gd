extends Node

## 全局游戏状态 (AutoLoad)
## 用于在使用 get_tree().change_scene_to_file() 重载场景时保持临时内存数据

var player_name: String = ""

func _ready() -> void:
	_ensure_ui_gamepad_actions()

func _ensure_ui_gamepad_actions() -> void:
	_ensure_action_with_joy_buttons("ui_accept", [JOY_BUTTON_A])
	_ensure_action_with_joy_buttons("ui_cancel", [JOY_BUTTON_B])
	_ensure_action_with_joy_buttons("ui_up", [JOY_BUTTON_DPAD_UP])
	_ensure_action_with_joy_buttons("ui_down", [JOY_BUTTON_DPAD_DOWN])
	_ensure_action_with_joy_buttons("ui_left", [JOY_BUTTON_DPAD_LEFT])
	_ensure_action_with_joy_buttons("ui_right", [JOY_BUTTON_DPAD_RIGHT])
	_ensure_action_with_keys("ui_accept", [KEY_A, KEY_ENTER, KEY_KP_ENTER])

func _ensure_action_with_joy_buttons(action_name: String, buttons: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	var existing_events: Array = InputMap.action_get_events(action_name)
	for button in buttons:
		var exists := false
		for ev in existing_events:
			if ev is InputEventJoypadButton and ev.button_index == button:
				exists = true
				break
		if exists:
			continue

		var joy_ev := InputEventJoypadButton.new()
		joy_ev.button_index = button
		InputMap.action_add_event(action_name, joy_ev)

func _ensure_action_with_keys(action_name: String, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	var existing_events: Array = InputMap.action_get_events(action_name)
	for keycode in keys:
		var exists := false
		for ev in existing_events:
			if ev is InputEventKey:
				var existing_key_ev := ev as InputEventKey
				if existing_key_ev.keycode == keycode or existing_key_ev.physical_keycode == keycode:
					exists = true
					break
		if exists:
			continue

		var key_ev := InputEventKey.new()
		key_ev.keycode = keycode
		key_ev.physical_keycode = keycode
		InputMap.action_add_event(action_name, key_ev)
