class_name UIManager
extends Control

## UI 管理器（挂在 main.tscn 根节点）
##
## 这版实现的核心目标：
## 1) 登录页与大厅页不再“同时实例化 + 显隐切换”，改为“单实例热切换”。
## 2) 任何时刻树里只保留一个活跃 UI 子场景，彻底避免 main/login 重复叠加。
## 3) 与 GameState 协同，保留玩家名，实现返回大厅时免重复登录。

@export_group("子场景资源")
@export var login_screen_scene: PackedScene
@export var main_lobby_scene: PackedScene

# 当前活跃的 UI 场景节点（登录页或大厅页，二选一）
var _active_screen: Control = null

# 便于连接信号与调用方法的强类型引用（当前不活跃时保持 null）
var _login_screen: LoginScreen = null
var _main_lobby: MainLobby = null

# 缓存玩家名，避免在切换过程中多次访问 AutoLoad
var _cached_player_name: String = ""


func _ready() -> void:
	_cached_player_name = _read_cached_player_name()

	# 启动分流逻辑：
	# - 没有名字：展示登录页
	# - 已有名字：直接进大厅（返回大厅/重进场景时可无缝恢复）
	if _cached_player_name.is_empty():
		_show_login()
	else:
		_show_lobby(_cached_player_name)


func _read_cached_player_name() -> String:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return ""
	return String(state.player_name).strip_edges()


func _save_cached_player_name(player_name: String) -> void:
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.player_name = player_name


func _clear_active_screen() -> void:
	# 切场景前先安全清理旧节点，避免两个 UI 同时存在造成“界面重影/错觉切场景”。
	if _active_screen and is_instance_valid(_active_screen):
		_active_screen.queue_free()

	_active_screen = null
	_login_screen = null
	_main_lobby = null


func _instantiate_ui_screen(scene_res: PackedScene, scene_name: String) -> Control:
	if scene_res == null:
		push_error("[UIManager] %s 资源未配置。请检查 main.tscn 导出属性。" % scene_name)
		return null

	var inst := scene_res.instantiate()
	if not (inst is Control):
		push_error("[UIManager] %s 不是 Control 场景，无法作为 UI 根节点挂载。" % scene_name)
		if inst:
			inst.queue_free()
		return null

	var ui := inst as Control
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return ui


func _show_login() -> void:
	_clear_active_screen()

	var screen := _instantiate_ui_screen(login_screen_scene, "LoginScreen")
	if screen == null:
		return

	_active_screen = screen
	add_child(_active_screen)

	if _active_screen is LoginScreen:
		_login_screen = _active_screen as LoginScreen
		_login_screen.login_successful.connect(_on_login_successful)
	else:
		push_warning("[UIManager] LoginScreen 未使用 LoginScreen 脚本，登录信号不会生效。")


func _show_lobby(player_name: String) -> void:
	_clear_active_screen()

	var screen := _instantiate_ui_screen(main_lobby_scene, "MainLobby")
	if screen == null:
		return

	_active_screen = screen
	add_child(_active_screen)

	if _active_screen is MainLobby:
		_main_lobby = _active_screen as MainLobby

		# 把玩家名喂给大厅，用于欢迎语显示。
		_main_lobby.set_player_name(player_name)

		# 保留信号连接，避免未来逻辑回归时再次改动 UIManager。
		_main_lobby.start_marathon.connect(_start_marathon_mode)
		_main_lobby.start_multiplayer.connect(_start_multiplayer_mode)
		_main_lobby.open_player_stats.connect(_open_player_stats)

		# 大厅入场动画不影响逻辑，仅作为表现层增强。
		_main_lobby.play_entrance_animation()
	else:
		push_warning("[UIManager] MainLobby 未使用 MainLobby 脚本，大厅交互信号不会生效。")


func _on_login_successful(player_name: String) -> void:
	_cached_player_name = player_name.strip_edges()
	_save_cached_player_name(_cached_player_name)
	_show_lobby(_cached_player_name)


func _start_marathon_mode() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _start_multiplayer_mode() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/multiplayer_setup.tscn")


## 打开玩家数据界面
func _open_player_stats() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/player_stats_screen.tscn")
