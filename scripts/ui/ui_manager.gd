class_name UIManager
extends Control

## UI管理器（挂载在 main.tscn 根节点）
## 负责场景状态机的跳转，比如从登录界面切换到主大厅，再由主大厅跳转到 Marathon 模式的 game.tscn。
## 使用 CanvasLayer 或者独立的 Control 作为外壳。

@export_group("子界面引用")
## 将我们在编辑器中组装好的子节点拖进来
@export var login_screen: Control
@export var main_lobby: Control

func _ready() -> void:
	# 连接子界面的信号
	if login_screen:
		login_screen.login_successful.connect(_on_login_successful)
	if main_lobby:
		main_lobby.start_marathon.connect(_start_marathon_mode)
		
	# 检查玩家是否已经输入过名字（充当简易的全局态存储以防刷新场景时重置）
	var config = ConfigFile.new()
	var saved_name = ""
	if config.load("user://settings.cfg") == OK:
		saved_name = config.get_value("Settings", "player_name", "")
		
	if saved_name != "":
		# 若有记录，直接免等进入大厅
		if main_lobby and main_lobby.has_method("set_player_name"):
			main_lobby.set_player_name(saved_name)
		show_lobby()
	else:
		# 初始状态：显示登录，隐藏主大厅
		show_login()

## ---------------------------------------------------------
## 界面切换逻辑
## ---------------------------------------------------------

func show_login() -> void:
	if login_screen: login_screen.show()
	if main_lobby: main_lobby.hide()

func show_lobby() -> void:
	if login_screen: login_screen.hide()
	if main_lobby:
		main_lobby.show()
		main_lobby.play_entrance_animation()

## ---------------------------------------------------------
## 信号回调
## ---------------------------------------------------------

func _on_login_successful(player_name: String) -> void:
	print("[UIManager] 玩家登录: ", player_name)
	
	# 存入配置文件，防止跳转游戏重返时丢失大厅状态
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		pass
	config.set_value("Settings", "player_name", player_name)
	config.save("user://settings.cfg")
	
	if main_lobby and main_lobby.has_method("set_player_name"):
		main_lobby.set_player_name(player_name)
	show_lobby()

func _start_marathon_mode() -> void:
	print("[UIManager] 启动 Marathon 模式！切换场景...")
	# 在这里离开 UI 领域，跳转进入游戏玩法场景（利用原生 get_tree().change_scene_to_file）
	get_tree().change_scene_to_file("res://scenes/game.tscn")
