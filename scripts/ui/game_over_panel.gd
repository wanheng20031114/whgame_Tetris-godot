extends CenterContainer

# 多人对战结算面板
# 功能:
# 1. 显示胜负结果
# 2. 提供再来一局和返回大厅按钮
# 3. 显示双方当前状态图标

@onready var result_label: Label = %ResultLabel
@onready var btn_rematch: Button = %RematchButton
@onready var btn_lobby: Button = %LobbyButton
@onready var local_name_label: Label = %LocalNameLabel
@onready var local_indicator: Label = %LocalIndicator
@onready var opponent_name_label: Label = %OpponentNameLabel
@onready var opponent_indicator: Label = %OpponentIndicator

# 状态颜色
const COLOR_READY := Color(0.18, 0.80, 0.34, 1.0)
const COLOR_WAITING := Color(0.90, 0.78, 0.20, 1.0)
const COLOR_DECLINED := Color(0.85, 0.20, 0.20, 1.0)

# 状态符号
const SYMBOL_WAITING := "\u25A1" # 中空方块
const SYMBOL_READY := "\u25CB" # 中空圆圈
const SYMBOL_DECLINED := "X" # 叉号

var _local_status: String = "none"
var _opponent_status: String = "none"
var _opponent_display_name: String = ""

func _enter_tree() -> void:
	# 编辑器中保持可见, 运行时自动隐藏
	if not Engine.is_editor_hint():
		visible = false

func _ready() -> void:
	btn_rematch.pressed.connect(_on_rematch_pressed)
	btn_lobby.pressed.connect(_on_lobby_pressed)

	NetworkManager.rematch_status_received.connect(_on_rematch_status_received)
	NetworkManager.game_started.connect(_on_game_restarted)
	NetworkManager.opponent_left.connect(_on_opponent_left)

	_update_button_texts()
	_update_player_labels()
	_update_indicators()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and is_node_ready():
		_update_button_texts()
		_update_player_labels()

func show_result(msg_key: String, opponent_name: String) -> void:
	_opponent_display_name = opponent_name
	_local_status = "none"
	# 对手离开时必须保持 declined，避免被初始化流程覆盖导致红色 X 不显示。
	if msg_key == "TXT_OPPONENT_LEFT_TITLE":
		_opponent_status = "declined"
	elif _opponent_status != "declined":
		_opponent_status = "none"

	result_label.text = tr(msg_key)
	_update_button_texts()
	_update_player_labels()
	_update_indicators()

	btn_rematch.disabled = false
	visible = true
	btn_rematch.grab_focus()

func hide_panel() -> void:
	visible = false

func _update_button_texts() -> void:
	if btn_rematch:
		btn_rematch.text = tr("TXT_REMATCH")
	if btn_lobby:
		btn_lobby.text = tr("TXT_RETURN_LOBBY")

func _update_player_labels() -> void:
	if local_name_label:
		local_name_label.text = tr("TXT_YOU")
	if opponent_name_label:
		if _opponent_display_name.strip_edges().is_empty():
			opponent_name_label.text = "???"
		else:
			opponent_name_label.text = _opponent_display_name

func _update_indicators() -> void:
	if local_indicator:
		var local_visual := _status_to_visual(_local_status)
		local_indicator.text = local_visual["symbol"]
		local_indicator.add_theme_color_override("font_color", local_visual["color"])
		local_indicator.add_theme_color_override("font_outline_color", local_visual["color"])
		local_indicator.add_theme_constant_override("outline_size", 5)
		local_indicator.add_theme_font_size_override("font_size", 50)

	if opponent_indicator:
		var opponent_visual := _status_to_visual(_opponent_status)
		opponent_indicator.text = opponent_visual["symbol"]
		opponent_indicator.add_theme_color_override("font_color", opponent_visual["color"])
		opponent_indicator.add_theme_color_override("font_outline_color", opponent_visual["color"])
		opponent_indicator.add_theme_constant_override("outline_size", 5)
		opponent_indicator.add_theme_font_size_override("font_size", 50)

func _status_to_visual(status: String) -> Dictionary:
	match status:
		"ready":
			return {"symbol": SYMBOL_READY, "color": COLOR_READY}
		"declined":
			return {"symbol": SYMBOL_DECLINED, "color": COLOR_DECLINED}
		_:
			return {"symbol": SYMBOL_WAITING, "color": COLOR_WAITING}

func _on_rematch_pressed() -> void:
	# 点击再来一局后, 本地状态先显示为准备好
	_local_status = "ready"
	_update_indicators()
	btn_rematch.disabled = true
	NetworkManager.request_rematch()

func _on_lobby_pressed() -> void:
	# 返回大厅视为取消重开
	NetworkManager.decline_rematch()
	get_tree().change_scene_to_file("res://scenes/ui/multiplayer_lobby.tscn")

func _on_rematch_status_received(my_status: String, opponent_status: String) -> void:
	_local_status = my_status
	_opponent_status = opponent_status
	_update_indicators()
	if opponent_status == "declined":
		btn_rematch.disabled = true

func _on_game_restarted(_opponent_name: String, _seed: int) -> void:
	hide_panel()

func _on_opponent_left() -> void:
	# 对手掉线也按取消状态处理
	_opponent_status = "declined"
	_update_indicators()
	btn_rematch.disabled = true
