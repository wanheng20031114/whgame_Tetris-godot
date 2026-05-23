class_name GuideSystem
extends Control

const BOARD_VIEW_SCENE := preload("res://scripts/ui/guide_board_view.gd")
const SCENARIO_RUNNER := preload("res://scripts/ui/guide_scenario_runner.gd")
const OVERVIEW_PAGE_SCENE := preload("res://scenes/ui/guide/overview_page.tscn")
const CHAPTER_PAGE_SCENE := preload("res://scenes/ui/guide/chapter_page.tscn")
const SIMULATION_PAGE_SCENE := preload("res://scenes/ui/guide/simulation_page.tscn")

const EMPTY := 0
const GARBAGE := 8
const SIM_ROWS := 20
const SIM_COLS := 10

## 攻击力表（对战标准）
const ATTACK_TABLE: Array = [
	["Single", "1", "0", "整理地形"],
	["Double", "2", "1", "基础输出"],
	["Triple", "3", "2", "中等输出"],
	["Tetris", "4", "4", "核心爆发"],
	["T-Spin Mini", "0", "0", "无攻击"],
	["T-Spin Single", "1", "2", "高效攻击"],
	["T-Spin Double", "2", "4", "核心进攻"],
	["T-Spin Triple", "3", "6", "最强爆发"],
]

## Combo 攻击力加成表
const COMBO_ATTACK_TABLE: Array = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5]

var chapters: Array = []
var selected_index: int = 0
var content_root: Control
var sidebar: VBoxContainer
var overview_button: Button
var board_view: Control
var feedback_label: Label
var objective_label: Label
var demo_timer: Timer
var demo_tween: Tween
var demo_action_label: Label
var demo_step: int = 0
var in_simulation: bool = false

var sim_id: String = ""
var sim_grid: Array = []
var sim_piece_type: int = PieceData.Type.I
var sim_rot: int = PieceData.RotationState.SPAWN
var sim_col: int = 4
var sim_row: int = 2
var sim_sequence: Array = []
var sim_sequence_index: int = 0
var sim_combo: int = 0
var sim_attempts: int = 0
var sim_success: bool = false
var sim_last_was_rotation: bool = false
var sim_started_msec: int = 0
var sim_hint_visible: bool = true
var sim_locked: bool = false
var scenario_runner: RefCounted


func _ready() -> void:
	_build_chapters()
	_build_shell()
	_show_overview()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree() and board_view:
		board_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if not in_simulation:
		return
	# 只有棋盘聚焦时才接受输入
	if board_view and not board_view.focused:
		return
	if event.is_action_pressed("ui_cancel"):
		if board_view:
			board_view.focused = false
			if board_view is Control:
				(board_view as Control).release_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		_sim_move(-1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		_sim_move(1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("soft_drop") or event.is_action_pressed("ui_down"):
		_sim_move(0, 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_cw") or event.is_action_pressed("ui_accept"):
		_sim_rotate(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_ccw"):
		_sim_rotate(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hard_drop"):
		_sim_hard_drop()
		get_viewport().set_input_as_handled()


func _build_chapters() -> void:
	chapters = [
		{
			"id": "attack",
			"number": "01",
			"title": "消除与攻击力",
			"tag": "核心",
			"time": "5 分钟",
			"summary": "不同消除方式的攻击力差异，以及 B2B、Combo 加成。",
			"concept": "对战中消行不是都一样。Single 通常没有攻击力，只用来整理地形。真正产生威胁的是 Tetris 四消、T-Spin、以及连续 Combo。\n\n理解攻击力表是一切进阶操作的基础——它解释了为什么高手不急着做小消，而是刻意保留结构来打出高价值消除。",
			"why": ["区分哪些消除有攻击价值", "理解 B2B（连续困难消除）额外 +1 行加成", "Combo 连击的额外攻击力递增机制"],
			"value": "Single 0 行 / Double 1 行 / Triple 2 行 / Tetris 4 行\nT-Spin Single 2 行 / T-Spin Double 4 行 / T-Spin Triple 6 行\nB2B 激活时额外 +1 行",
			"steps": ["先看攻击力表，记住各消除的行数", "注意 Tetris 和 T-Spin Double 都是 4 行攻击，但 T-Spin 用更少空间", "B2B：连续打出 Tetris 或 T-Spin 可激活，额外 +1 行", "Combo：连续消行不中断，按次数额外加攻击力"],
			"mistakes": ["把所有消行都当成一样好", "为了小消破坏 Tetris 井或 T 槽", "不知道 B2B 和 Combo 的加成存在"],
			"sim": "tetris"
		},
		{
			"id": "wallkick",
			"number": "02",
			"title": "Wall Kick 踢墙",
			"tag": "机制",
			"time": "3 分钟",
			"summary": "方块旋转时碰到障碍，系统自动尝试偏移位置来完成旋转。",
			"concept": "SRS 旋转系统中，当方块旋转后与墙壁或其它方块重叠时，系统会按顺序尝试多个偏移位置（称为 kick）。如果某个偏移位置合法，方块就会偏移到那个位置完成旋转。\n\n这意味着方块的旋转中心可能会发生横向甚至纵向位移。踢墙是 T-Spin 能够成立的核心原理。",
			"why": ["理解旋转不只是原地转", "踢墙让方块能进入看似不可能的位置", "T-Spin 的本质就是利用踢墙偏移"],
			"value": "踢墙本身不产生攻击力，但它是实现 T-Spin 等高价值消除的前提条件。",
			"steps": ["观察演示中 L 方块贴墙旋转时中心点的位移", "红色圆圈标记了旋转中心点位置", "旋转前后中心点的横向偏移就是踢墙产生的位移", "所有方块（O 除外）都有踢墙数据"],
			"mistakes": ["以为旋转一定是原地的", "不知道不同方块的踢墙表不同", "忽略 I 方块有独立的踢墙表"],
			"sim": "wallkick"
		},
		{
			"id": "combo",
			"number": "03",
			"title": "Combo 连击",
			"tag": "进攻",
			"time": "5 分钟",
			"summary": "每次落块都消行，连续不中断就是 Combo。",
			"concept": "Combo 的规则很简单：只要每次锁定方块都消除了至少一行，Combo 计数就 +1。一旦某次落块没有消行，Combo 归零。\n\nCombo 的额外攻击力按次数递增：",
			"why": ["训练连续消行的节奏感", "高 Combo 能累积大量额外攻击力", "适合在残局或地形混乱时转守为攻"],
			"value": "Combo 额外攻击力：1→0  2→0  3→+1  4→+1  5→+2  6→+2  7→+3  8→+3  9→+4  10→+4  11→+4  12→+5",
			"steps": ["观察右侧演示：O 方块持续落入右侧 2 列空位", "每次消除 2 行，Combo 计数持续增加", "注意 Combo 3 开始产生额外攻击力", "额外攻击力会叠加在消除本身的攻击力之上"],
			"mistakes": ["中途有一次没消行，Combo 立刻归零", "每步都想做大消反而容易中断", "忽略了 Combo 的攻击力加成是额外的"],
			"sim": "combo"
		},
		{
			"id": "tspin",
			"number": "04",
			"title": "T-Spin Double",
			"tag": "核心进攻",
			"time": "5 分钟",
			"summary": "T 方块通过旋转卡入 T 槽，同时消除 2 行，攻击力 4 行。",
			"concept": "T-Spin Double（TSD）是对战中最常用的高价值消除。它利用踢墙机制将 T 方块旋入一个特定的槽位，同时消除 2 行。\n\n攻击力 4 行，与 Tetris 相同，但只需要 2 行高度的结构就能完成——空间效率极高。配合 B2B 可达到 5 行攻击。",
			"why": ["TSD 攻击力 = Tetris 但空间更省", "配合 B2B 可达 5 行攻击", "是进阶对战的核心技巧"],
			"value": "T-Spin Double 基础攻击 4 行，B2B 加成后 5 行。\n用 2 行结构换取 4 行攻击，空间效率是 Tetris 的 2 倍。",
			"steps": ["准备一个 T 形槽：底部 2 行留出 T 方块旋入的空间", "保留入口：T 槽上方需要留出通道", "将 T 方块移到槽口上方", "旋转卡入：利用踢墙让 T 方块嵌入槽位", "锁定后系统判定为 T-Spin（最后操作必须是旋转）"],
			"mistakes": ["直接放下而不是旋转进入", "T 槽结构不对，无法消 2 行", "入口被提前堵死"],
			"sim": "tspin"
		}
	]


func _build_shell() -> void:
	content_root = %ContentRoot
	sidebar = %ChaptersList
	overview_button = %OverviewButton

	var header := get_node_or_null("Page/Header") as PanelContainer
	if header:
		header.add_theme_stylebox_override("panel", _style(Color("ffffff"), Color("e2e8f0"), 0, 0))

	var sidebar_panel := get_node_or_null("Page/BodyMargin/Body/SidebarPanel") as PanelContainer
	if sidebar_panel:
		sidebar_panel.add_theme_stylebox_override("panel", _style(Color("f8fbff"), Color("d8e4f1"), 8, 1))

	var back := %BackButton as Button
	_style_button(back, false)
	back.add_theme_stylebox_override("normal", _style(Color("ffffff"), Color("cbd5e1"), 8, 1))
	back.add_theme_stylebox_override("hover", _style(Color("e0f2fe"), Color("38bdf8"), 8, 1))
	back.add_theme_stylebox_override("pressed", _style(Color("bae6fd"), Color("0284c7"), 8, 1))
	back.add_theme_stylebox_override("focus", _style(Color("e0f2fe"), Color("0284c7"), 8, 1))
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/main.tscn"))

	overview_button.pressed.connect(_show_overview)

	_rebuild_sidebar()

	demo_timer = Timer.new()
	add_child(demo_timer)


func _rebuild_sidebar() -> void:
	for child in sidebar.get_children():
		child.queue_free()

	if overview_button:
		_style_sidebar_button(overview_button, selected_index < 0)

	for i in range(chapters.size()):
		var chapter: Dictionary = chapters[i]
		sidebar.add_child(_sidebar_button("%s  %s" % [chapter["number"], chapter["title"]], i))


func _sidebar_button(text: String, index: int) -> Button:
	var btn := Button.new()
	btn.text = "  " + text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 42)
	btn.focus_mode = Control.FOCUS_ALL
	var active := (index == selected_index and not in_simulation) or (index == -1 and selected_index < 0)
	_style_sidebar_button(btn, active)
	if index == -1:
		btn.pressed.connect(_show_overview)
	else:
		btn.pressed.connect(_show_chapter.bind(index))
	return btn


func _style_sidebar_button(btn: Button, active: bool) -> void:
	var normal_color := Color("e0f2fe") if active else Color("ffffff")
	var border_color := Color("0284c7") if active else Color("d8e4f1")
	btn.add_theme_stylebox_override("normal", _style(normal_color, border_color, 8, 1))
	btn.add_theme_stylebox_override("hover", _style(Color("f0f9ff"), Color("38bdf8"), 8, 1))
	btn.add_theme_stylebox_override("pressed", _style(Color("bae6fd"), Color("0ea5e9"), 8, 1))
	btn.add_theme_stylebox_override("focus", _style(Color("e0f2fe"), Color("0284c7"), 8, 1))
	btn.add_theme_color_override("font_color", Color("12345a"))
	btn.add_theme_color_override("font_hover_color", Color("075985"))
	btn.add_theme_color_override("font_pressed_color", Color("0369a1"))
	btn.add_theme_color_override("font_focus_color", Color("075985"))


func _show_overview() -> void:
	in_simulation = false
	selected_index = -1
	_rebuild_sidebar()
	_clear_content()
	_stop_demo_animation()

	var page := OVERVIEW_PAGE_SCENE.instantiate()
	content_root.add_child(page)
	_style_panel_node(page.get_node("Page/HeroPanel"))
	_style_panel_node(page.get_node("Page/PathPanel"))
	_style_panel_node(page.get_node("Page/CardsPanel"))

	var path := page.get_node("%PathBox") as HBoxContainer
	for item in ["消除攻击力", "Wall Kick", "Combo", "T-Spin Double"]:
		path.add_child(_chip(item, Color("ecfdf5"), Color("047857")))

	var cards_grid := page.get_node("%CardsGrid") as GridContainer
	for i in range(chapters.size()):
		cards_grid.add_child(_chapter_card(i))

	var attack_host := page.get_node("%AttackTableHost") as VBoxContainer
	attack_host.add_child(_attack_table())


func _chapter_card(index: int) -> Control:
	var chapter: Dictionary = chapters[index]
	var card := _panel()
	card.custom_minimum_size = Vector2(360, 170)
	var margin := _margin(card, 18, 16, 18, 16)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	top.add_child(_chip(chapter["number"], Color("dbeafe"), Color("1d4ed8")))
	var title := _label(chapter["title"], 20, Color("0f1f45"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_chip(chapter["tag"], Color("fef3c7"), Color("92400e")))

	box.add_child(_paragraph(chapter["summary"]))
	box.add_child(_label("预计 " + String(chapter["time"]), 13, Color("64748b")))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	var read_btn := _primary_button("查看", false)
	read_btn.pressed.connect(_show_chapter.bind(index))
	buttons.add_child(read_btn)
	var sim_btn := _primary_button("开始模拟", true)
	sim_btn.pressed.connect(_start_simulation.bind(chapter["sim"], index))
	buttons.add_child(sim_btn)
	return card


func _show_chapter(index: int) -> void:
	in_simulation = false
	selected_index = index
	_rebuild_sidebar()
	_clear_content()
	var chapter: Dictionary = chapters[index]

	var page := CHAPTER_PAGE_SCENE.instantiate()
	content_root.add_child(page)
	_style_panel_node(page.get_node("ArticleScroll/Article/TitlePanel"))
	_style_panel_node(page.get_node("ArticleScroll/Article/ConceptSection"))
	_style_panel_node(page.get_node("ArticleScroll/Article/WhySection"))
	_style_panel_node(page.get_node("ArticleScroll/Article/ValueSection"))
	_style_panel_node(page.get_node("ArticleScroll/Article/StepsSection"))
	_style_panel_node(page.get_node("ArticleScroll/Article/MistakesSection"))
	_style_panel_node(page.get_node("DemoPanel"))

	var chip := page.get_node("%Chip") as Label
	chip.text = "  %s / %s / %s  " % [chapter["number"], chapter["tag"], chapter["time"]]
	chip.add_theme_stylebox_override("normal", _style(Color("e0f2fe"), Color("e0f2fe"), 8, 0))
	(page.get_node("%Title") as Label).text = chapter["title"]
	(page.get_node("%Summary") as Label).text = chapter["summary"]
	(page.get_node("%ConceptText") as Label).text = chapter["concept"]
	(page.get_node("%ValueText") as Label).text = chapter["value"]

	_populate_static_list(page.get_node("%WhyBox") as VBoxContainer, chapter["why"])
	_populate_static_list(page.get_node("%StepsBox") as VBoxContainer, chapter["steps"])
	_populate_static_list(page.get_node("%MistakesBox") as VBoxContainer, chapter["mistakes"])

	var sim_btn := page.get_node("%SimButton") as Button
	_style_button(sim_btn, true)
	sim_btn.pressed.connect(_start_simulation.bind(chapter["sim"], index))
	var next_btn := page.get_node("%NextButton") as Button
	_style_button(next_btn, false)
	next_btn.disabled = index >= chapters.size() - 1
	next_btn.pressed.connect(_show_chapter.bind(index + 1))

	demo_action_label = page.get_node("%ActionLabel") as Label
	demo_action_label.text = "准备"
	demo_action_label.add_theme_stylebox_override("normal", _style(Color("ecfdf5"), Color("bbf7d0"), 8, 1))
	board_view = page.get_node("%BoardView")
	_start_demo_for_chapter(chapter["sim"])


func _start_demo_for_chapter(chapter_sim_id: String) -> void:
	sim_id = chapter_sim_id
	demo_step = 0
	if board_view:
		board_view.show_ghost = true
		# Wall Kick 和 T-Spin 演示显示中心点
		board_view.show_center_point = (sim_id == "wallkick" or sim_id == "tspin")
	_play_demo_cycle()


func _play_demo_cycle() -> void:
	if board_view == null or in_simulation or selected_index < 0:
		return
	_stop_demo_animation()

	var runner: RefCounted = SCENARIO_RUNNER.new()
	runner.setup(sim_id, demo_step)
	var demo := _build_demo_sequence(runner)
	var frames: Array = demo["frames"]
	if frames.is_empty():
		return

	var targets: Array = runner.target_cells()
	var focus: Array = runner.focus_cells()

	board_view.set_state(SCENARIO_RUNNER.copy_grid(frames[0]["grid"]), frames[0]["from"], targets, runner.highlight_rows(), focus)
	board_view.set_effect_text("")
	_set_demo_action(frames[0]["label"])

	demo_tween = create_tween()
	demo_tween.set_trans(Tween.TRANS_SINE)
	demo_tween.set_ease(Tween.EASE_IN_OUT)
	demo_tween.tween_interval(0.25)

	for frame in frames:
		demo_tween.tween_callback(_set_demo_action.bind(frame["label"]))
		demo_tween.tween_method(
			Callable(self, "_demo_interpolate_piece").bind(frame["grid"], frame["from"], frame["to"], targets, frame.get("rows", []), focus),
			0.0,
			1.0,
			float(frame.get("duration", 0.08))
		)

	demo_tween.tween_callback(_set_demo_action.bind("锁定"))
	demo_tween.tween_callback(func(): board_view.set_state(demo["locked_grid"], {}, targets, demo["rows"], []))

	# 播放消行特效
	if not (demo["rows"] as Array).is_empty():
		demo_tween.tween_callback(func():
			if board_view:
				board_view.play_clear_effect(demo["rows"])
		)

	demo_tween.tween_interval(0.22)
	demo_tween.tween_callback(_set_demo_action.bind("消除"))
	demo_tween.tween_callback(func():
		board_view.set_state(demo["cleared_grid"], {}, [], [], [])
		board_view.set_effect_text(demo["effect"])
	)
	demo_tween.tween_interval(1.05)
	demo_tween.tween_callback(func(): board_view.set_effect_text(""))
	demo_tween.tween_callback(func():
		demo_step = _next_demo_step()
		demo_tween = null
		call_deferred("_play_demo_cycle")
	)


func _build_demo_sequence(runner: RefCounted) -> Dictionary:
	var frames: Array = []
	for op in _demo_operations(runner.scene_id, runner.phase):
		match String(op["op"]):
			"drop_to":
				_append_drop_frames(frames, runner, int(op["row"]), String(op["label"]))
			"hard_drop":
				_append_hard_drop_frames(frames, runner, String(op["label"]))
			"move":
				_append_move_frames(frames, runner, int(op["dx"]), int(op["count"]), String(op["label"]))
			"rotate":
				_append_rotate_frame(frames, runner, int(op["direction"]), String(op["label"]))
			"wait":
				_append_wait_frame(frames, runner, float(op.get("duration", 1.0)), String(op["label"]))

	var locked_grid: Array = runner.grid_with_active()
	var result: Dictionary = runner.lock_piece()
	return {
		"frames": frames,
		"locked_grid": locked_grid,
		"cleared_grid": SCENARIO_RUNNER.copy_grid(runner.grid),
		"rows": result["rows"],
		"effect": runner.effect_text(int(result["cleared"]), bool(result["spin"]))
	}


func _append_drop_frames(frames: Array, runner: RefCounted, target_row: int, label: String) -> void:
	while runner.row < target_row:
		var from_piece: Dictionary = runner.piece_dict()
		if not runner.try_move(0, 1):
			break
		frames.append(_demo_frame(runner, from_piece, runner.piece_dict(), label, 0.045))


func _append_hard_drop_frames(frames: Array, runner: RefCounted, label: String) -> void:
	while true:
		var from_piece: Dictionary = runner.piece_dict()
		if not runner.try_move(0, 1):
			break
		frames.append(_demo_frame(runner, from_piece, runner.piece_dict(), label, 0.03))


func _append_wait_frame(frames: Array, runner: RefCounted, duration: float, label: String) -> void:
	var piece_dict: Dictionary = runner.piece_dict()
	frames.append({
		"grid": SCENARIO_RUNNER.copy_grid(runner.grid),
		"from": piece_dict,
		"to": piece_dict,
		"label": label,
		"rows": runner.highlight_rows(),
		"duration": duration
	})


func _append_move_frames(frames: Array, runner: RefCounted, dx: int, count: int, label: String) -> void:
	var direction := 1 if dx > 0 else -1
	for _i in range(count):
		var from_piece: Dictionary = runner.piece_dict()
		if not runner.try_move(direction, 0):
			break
		frames.append(_demo_frame(runner, from_piece, runner.piece_dict(), label, 0.075))


func _append_rotate_frame(frames: Array, runner: RefCounted, direction: int, label: String) -> void:
	var from_piece: Dictionary = runner.piece_dict()
	if runner.try_rotate(direction):
		frames.append(_demo_frame(runner, from_piece, runner.piece_dict(), label, 0.22))


func _demo_frame(runner: RefCounted, from_piece: Dictionary, to_piece: Dictionary, label: String, duration: float) -> Dictionary:
	return {
		"grid": SCENARIO_RUNNER.copy_grid(runner.grid),
		"from": from_piece,
		"to": to_piece,
		"label": label,
		"rows": runner.highlight_rows(),
		"duration": duration
	}


func _demo_operations(scene_id: String, phase: int) -> Array:
	if scene_id == "tspin":
		return [
			{"op": "rotate", "direction": 1, "label": "顺时针旋转，调整入口方向"},
			{"op": "drop_to", "row": 18, "label": "软降到槽口上方"},
			{"op": "rotate", "direction": 1, "label": "顺时针旋转，T 方块旋入 T 槽"}
		]
	if scene_id == "wallkick":
		return [
			{"op": "rotate", "direction": -1, "label": "逆时针旋转 90°"},
			{"op": "move", "dx": 1, "count": 3, "label": "向右移动直到贴住墙壁"},
			{"op": "wait", "duration": 1.0, "label": "贴墙停顿"},
			{"op": "rotate", "direction": 1, "label": "顺时针旋转 90°：踢墙，中心点向左移 1 格"},
			{"op": "wait", "duration": 1.5, "label": "观察踢墙位移"},
			{"op": "rotate", "direction": -1, "label": "再次逆时针旋转 90°"},
			{"op": "move", "dx": 1, "count": 1, "label": "右移贴住墙壁"},
			{"op": "hard_drop", "label": "下落到底部"},
			{"op": "wait", "duration": 1.0, "label": "等待旋入时机"},
			{"op": "rotate", "direction": 1, "label": "顺时针旋转：踢墙旋入，完成 L-Spin"}
		]
	if scene_id == "combo":
		# O 方块直接硬降到右侧 2 列
		return [
			{"op": "move", "dx": 1, "count": 1, "label": "移动到右侧空位上方"},
			{"op": "drop_to", "row": 19, "label": "下落到底部，消除 2 行"}
		]
	# tetris
	return [
		{"op": "drop_to", "row": 8, "label": "软降"},
		{"op": "move", "dx": 1, "count": 3, "label": "右移到井旁"},
		{"op": "rotate", "direction": 1, "label": "顺时针旋转 90°"},
		{"op": "move", "dx": 1, "count": 1, "label": "贴住井口"},
		{"op": "drop_to", "row": 17, "label": "下落插入井"}
	]


func _demo_interpolate_piece(value: float, grid: Array, from_piece: Dictionary, to_piece: Dictionary, targets: Array, rows: Array, focus: Array) -> void:
	if board_view == null:
		return
	var piece := {
		"type": int(from_piece.get("type", PieceData.Type.T)),
		"rot": int(to_piece.get("rot", from_piece.get("rot", PieceData.RotationState.SPAWN))) if value >= 0.55 else int(from_piece.get("rot", PieceData.RotationState.SPAWN)),
		"col": lerpf(float(from_piece.get("col", 4.0)), float(to_piece.get("col", 4.0)), value),
		"row": lerpf(float(from_piece.get("row", 4.0)), float(to_piece.get("row", 4.0)), value)
	}
	board_view.set_state(grid, piece, targets, rows, focus)


func _set_demo_action(text: String) -> void:
	if demo_action_label:
		demo_action_label.text = "  " + text + "  "


func _stop_demo_animation() -> void:
	if demo_tween and demo_tween.is_running():
		demo_tween.kill()
	demo_tween = null


func _next_demo_step() -> int:
	if sim_id == "combo":
		return (demo_step + 1) % 5
	return 0


func _start_simulation(chapter_sim_id: String, chapter_index: int) -> void:
	in_simulation = true
	selected_index = chapter_index
	sim_id = chapter_sim_id
	_rebuild_sidebar()
	_clear_content()
	_stop_demo_animation()

	var page := SIMULATION_PAGE_SCENE.instantiate()
	content_root.add_child(page)
	_style_panel_node(page.get_node("SidePanel"))
	_style_panel_node(page.get_node("BoardPanel"))

	objective_label = page.get_node("%ObjectiveLabel")
	feedback_label = page.get_node("%FeedbackLabel")
	board_view = page.get_node("%BoardView")
	board_view.show_ghost = true
	# Wall Kick 和 T-Spin 模拟显示中心点
	board_view.show_center_point = (sim_id == "wallkick" or sim_id == "tspin")

	_connect_sim_button(page, "ResetButton", false, _reset_simulation)
	_connect_sim_button(page, "ExitButton", false, _show_chapter.bind(chapter_index))

	_reset_simulation()


func _reset_simulation() -> void:
	scenario_runner = SCENARIO_RUNNER.new()
	scenario_runner.setup(sim_id, 0)
	sim_grid = scenario_runner.grid
	sim_sequence_index = 0
	sim_combo = 0
	sim_attempts = 0
	sim_success = false
	sim_locked = false
	sim_last_was_rotation = false
	sim_hint_visible = true
	sim_started_msec = Time.get_ticks_msec()

	match sim_id:
		"tspin":
			_set_feedback("目标：将 T 方块旋入 T 槽，同时消除 2 行，完成 T-Spin Double。")
		"combo":
			_set_feedback("目标：用 O 方块连续落入右侧空位消行，完成 Combo 5。")
		"wallkick":
			_set_feedback("目标：将 L 方块旋转，观察踢墙导致的中心点偏移。")
		_:
			_set_feedback("目标：将 I 方块旋成竖直，放入右侧井，完成 Tetris 四消。")

	_update_objective()
	_refresh_sim_view()


func _update_objective() -> void:
	if objective_label == null:
		return
	match sim_id:
		"tspin":
			objective_label.text = "T-Spin Double 模拟"
		"combo":
			objective_label.text = "Combo 模拟  当前 Combo: %d" % sim_combo
		"wallkick":
			objective_label.text = "Wall Kick 踢墙模拟"
		_:
			objective_label.text = "Tetris 四消模拟"


func _set_feedback(text: String, success: bool = false, danger: bool = false) -> void:
	if feedback_label == null:
		return
	feedback_label.text = text
	if success:
		feedback_label.add_theme_color_override("font_color", Color("047857"))
	elif danger:
		feedback_label.add_theme_color_override("font_color", Color("b45309"))
	else:
		feedback_label.add_theme_color_override("font_color", Color("475569"))


func _spawn_sim_piece(piece_type: int, col: int, row: int, rot: int = PieceData.RotationState.SPAWN) -> void:
	sim_piece_type = piece_type
	sim_col = col
	sim_row = row
	sim_rot = rot
	sim_last_was_rotation = false


func _sim_move(dx: int, dy: int) -> void:
	if sim_success or sim_locked or scenario_runner == null:
		return
	if scenario_runner.try_move(dx, dy):
		_refresh_sim_view()


func _sim_rotate(direction: int) -> void:
	if sim_success or sim_locked or scenario_runner == null:
		return
	if scenario_runner.try_rotate(direction):
		_refresh_sim_view()
		return
	_set_feedback("这里转不进去。先移动到合适位置再旋转。", false, true)


func _sim_hard_drop() -> void:
	if sim_success or sim_locked or scenario_runner == null:
		return
	scenario_runner.hard_drop()
	_lock_sim_piece()


func _sim_lock_now() -> void:
	if sim_success or sim_locked or scenario_runner == null:
		return
	if scenario_runner.is_valid(scenario_runner.piece_type, scenario_runner.rot, scenario_runner.col, scenario_runner.row + 1):
		_set_feedback("还没有贴住地形。继续软降，或者用硬降。", false, true)
		return
	_lock_sim_piece()


func _lock_sim_piece() -> void:
	sim_attempts += 1

	var result: Dictionary = scenario_runner.lock_piece()
	var cleared := int(result["cleared"])
	var cleared_rows: Array = result["rows"]
	var elapsed := float(Time.get_ticks_msec() - sim_started_msec) / 1000.0

	# 播放消行特效
	if cleared > 0 and board_view:
		board_view.play_clear_effect(cleared_rows)

	match sim_id:
		"tspin":
			if scenario_runner.piece_type == PieceData.Type.T and bool(result["spin"]) and cleared >= 2:
				sim_success = true
				sim_locked = true
				_set_feedback("成功！T-Spin Double —— 旋入 T 槽消除 2 行，攻击力 4 行。用时 %.1f 秒。" % elapsed, true)
			elif scenario_runner.piece_type == PieceData.Type.T and bool(result["spin"]) and cleared == 1:
				sim_locked = true
				_set_feedback("完成了 T-Spin Single（消 1 行），但目标是 T-Spin Double（消 2 行）。检查 T 槽结构，按重置再试。", false, true)
			else:
				sim_locked = true
				_set_feedback("没有达成 T-Spin。最后一步必须是旋转卡入，而且要消 2 行。按重置再试。", false, true)
		"combo":
			if cleared > 0:
				sim_combo += 1
				if sim_combo >= 5:
					sim_success = true
					sim_locked = true
					_set_feedback("成功！Combo 5 —— 连续 5 次消行，用时 %.1f 秒。" % elapsed, true)
				else:
					var extra: int = int(COMBO_ATTACK_TABLE[mini(sim_combo, COMBO_ATTACK_TABLE.size() - 1)])
					_set_feedback("Combo %d！额外攻击力 +%d 行。继续保持连击。" % [sim_combo, extra], true)
					sim_sequence_index += 1
					scenario_runner.phase = sim_sequence_index
					scenario_runner.spawn(PieceData.Type.O, 7, 2, PieceData.RotationState.SPAWN)
					sim_locked = false
			else:
				sim_combo = 0
				sim_locked = true
				_set_feedback("连击中断——这次落块没有消行。Combo 要求每次都消行。", false, true)
		"wallkick":
			sim_locked = true
			if bool(result["spin"]) and cleared >= 2:
				sim_success = true
				_set_feedback("成功！L-Spin —— 最后一次旋转靠踢墙进入空洞，并完成 2 行消除。", true)
			else:
				_set_feedback("还没有完成 L-Spin。需要最后一步靠踢墙旋入右下角，并完成 2 行消除。", false, true)
		_:
			if scenario_runner.piece_type == PieceData.Type.I and cleared == 4:
				sim_success = true
				sim_locked = true
				_set_feedback("成功！Tetris 四消 —— I 方块竖直插入井中消除 4 行，攻击力 4 行。用时 %.1f 秒。" % elapsed, true)
			else:
				sim_locked = true
				_set_feedback("没有达成四消。I 方块要旋成竖直放入井中。按重置再试。", false, true)

	_update_objective()
	_refresh_sim_view()


func _refresh_sim_view() -> void:
	if board_view == null or scenario_runner == null:
		return
	sim_grid = scenario_runner.grid
	board_view.set_state(
		scenario_runner.grid,
		{} if sim_locked else scenario_runner.piece_dict(),
		scenario_runner.target_cells() if sim_hint_visible else [],
		scenario_runner.highlight_rows(),
		scenario_runner.focus_cells()
	)


func _sim_target_cells() -> Array:
	match sim_id:
		"tspin":
			return _piece_cells(PieceData.Type.T, PieceData.RotationState.TWO, 5, 18)
		"combo":
			if sim_sequence_index == 0:
				return _piece_cells(PieceData.Type.O, PieceData.RotationState.SPAWN, 8, 19)
			return _piece_cells(PieceData.Type.O, PieceData.RotationState.SPAWN, 8, 19 - sim_sequence_index * 2)
		"wallkick":
			return _piece_cells(PieceData.Type.L, PieceData.RotationState.R, 8, 12)
		_:
			return _piece_cells(PieceData.Type.I, PieceData.RotationState.R, 8, 17)


func _sim_highlight_rows() -> Array:
	match sim_id:
		"tspin":
			return [18, 19]
		"combo":
			return [18, 19] if sim_sequence_index == 0 else [19]
		"wallkick":
			return []
		_:
			return [16, 17, 18, 19]


func _sim_valid(type: int, rot_state: int, col_pos: int, row_pos: int) -> bool:
	for offset in PieceData.SHAPES[type][rot_state]:
		var c := col_pos + int(offset.x)
		var r := row_pos + int(offset.y)
		if c < 0 or c >= SIM_COLS:
			return false
		if r >= SIM_ROWS:
			return false
		if r < 0:
			continue
		if int(sim_grid[r][c]) != EMPTY:
			return false
	return true


func _piece_cells(type: int, rot_state: int, col_pos: int, row_pos: int) -> Array:
	var cells: Array = []
	for offset in PieceData.SHAPES[type][rot_state]:
		cells.append(Vector2i(col_pos + int(offset.x), row_pos + int(offset.y)))
	return cells


func _clear_sim_lines() -> int:
	var new_grid: Array = []
	var cleared := 0
	for grid_row in range(SIM_ROWS):
		var full := true
		for grid_col in range(SIM_COLS):
			if int(sim_grid[grid_row][grid_col]) == EMPTY:
				full = false
				break
		if full:
			cleared += 1
		else:
			new_grid.append(sim_grid[grid_row])
	for _i in range(cleared):
		new_grid.insert(0, _empty_row())
	sim_grid = new_grid
	return cleared


func _fill_tetris_grid(grid: Array) -> void:
	for grid_row in range(16, 20):
		for grid_col in range(0, 9):
			grid[grid_row][grid_col] = GARBAGE


func _fill_tspin_grid(grid: Array) -> void:
	for grid_col in range(SIM_COLS):
		if grid_col < 4 or grid_col > 6:
			grid[18][grid_col] = GARBAGE
	grid[19][3] = GARBAGE
	grid[19][4] = GARBAGE
	grid[19][6] = GARBAGE
	grid[19][7] = GARBAGE
	grid[17][4] = GARBAGE


func _fill_combo_phase_grid(grid: Array, phase: int) -> void:
	for grid_row in range(16, 20):
		for grid_col in range(SIM_COLS):
			var hole_a := 4 if phase != 1 else 8
			var hole_b := 5 if phase != 1 else 9
			if grid_col != hole_a and grid_col != hole_b:
				grid[grid_row][grid_col] = GARBAGE
	if phase == 0:
		for grid_row in [18, 19]:
			for grid_col in range(SIM_COLS):
				if grid_col != 4 and grid_col != 5:
					grid[grid_row][grid_col] = GARBAGE
	elif phase == 1:
		for grid_row in range(16, 20):
			for grid_col in range(SIM_COLS):
				if grid_col != 8:
					grid[grid_row][grid_col] = GARBAGE
	else:
		for grid_col in range(SIM_COLS):
			if grid_col < 4 or grid_col > 6:
				grid[19][grid_col] = GARBAGE


func _empty_grid() -> Array:
	var data: Array = []
	for _r in range(SIM_ROWS):
		data.append(_empty_row())
	return data


func _empty_row() -> Array:
	var grid_row: Array = []
	for _c in range(SIM_COLS):
		grid_row.append(EMPTY)
	return grid_row


func _attack_table() -> Control:
	var panel := _panel()
	var margin := _margin(panel, 20, 18, 20, 18)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	# 标题
	box.add_child(_label("攻击力速查表", 22, Color("0f1f45")))
	box.add_child(_paragraph("对战中，消除行数不等于攻击力。以下是各消除类型发送的垃圾行数："))

	# 攻击力表格
	var table_grid := GridContainer.new()
	table_grid.columns = 4
	table_grid.add_theme_constant_override("h_separation", 4)
	table_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(table_grid)

	# 表头
	for header_text in ["消除类型", "消除行数", "攻击力", "备注"]:
		var header := _label(header_text, 14, Color("ffffff"))
		header.custom_minimum_size = Vector2(120, 32)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		header.add_theme_stylebox_override("normal", _style(Color("1d4ed8"), Color("1d4ed8"), 4, 0))
		table_grid.add_child(header)

	# 数据行
	for row_data in ATTACK_TABLE:
		var is_high := int(row_data[2]) >= 4
		var bg := Color("fef3c7") if is_high else Color("f8fafc")
		for cell_idx in range(4):
			var cell_label := _label(row_data[cell_idx], 14, Color("1e293b"))
			cell_label.custom_minimum_size = Vector2(120, 30)
			cell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell_label.add_theme_stylebox_override("normal", _style(bg, Color("e2e8f0"), 2, 1))
			table_grid.add_child(cell_label)

	# B2B 说明
	var b2b_panel := _panel()
	b2b_panel.add_theme_stylebox_override("panel", _style(Color("eff6ff"), Color("93c5fd"), 8, 1))
	var b2b_margin := _margin(b2b_panel, 14, 10, 14, 10)
	var b2b_box := VBoxContainer.new()
	b2b_box.add_theme_constant_override("separation", 4)
	b2b_margin.add_child(b2b_box)
	b2b_box.add_child(_label("B2B（Back-to-Back）", 15, Color("1d4ed8")))
	b2b_box.add_child(_paragraph("连续打出「困难消除」（Tetris 或 T-Spin）不中断，额外 +1 行攻击力。中间穿插普通消除会中断 B2B。"))
	box.add_child(b2b_panel)

	# Combo 说明
	var combo_panel := _panel()
	combo_panel.add_theme_stylebox_override("panel", _style(Color("ecfdf5"), Color("86efac"), 8, 1))
	var combo_margin := _margin(combo_panel, 14, 10, 14, 10)
	var combo_box := VBoxContainer.new()
	combo_box.add_theme_constant_override("separation", 4)
	combo_margin.add_child(combo_box)
	combo_box.add_child(_label("Combo 额外攻击力", 15, Color("047857")))
	combo_box.add_child(_paragraph("连击次数 → 额外行数：1→0  2→0  3→+1  4→+1  5→+2  6→+2  7→+3  8→+3  9→+4  10+→+4~5"))
	combo_box.add_child(_paragraph("额外攻击力叠加在消除本身的攻击力之上。"))
	box.add_child(combo_panel)

	return panel


func _text_section(title: String, text: String) -> Control:
	var panel := _panel()
	var margin := _margin(panel, 18, 16, 18, 16)
	var section_box := VBoxContainer.new()
	section_box.add_theme_constant_override("separation", 8)
	margin.add_child(section_box)
	section_box.add_child(_label(title, 19, Color("0f1f45")))
	section_box.add_child(_paragraph(text))
	return panel


func _list_section(title: String, items: Array) -> Control:
	var panel := _panel()
	var margin := _margin(panel, 18, 16, 18, 16)
	var section_box := VBoxContainer.new()
	section_box.add_theme_constant_override("separation", 8)
	margin.add_child(section_box)
	section_box.add_child(_label(title, 19, Color("0f1f45")))
	for item in items:
		section_box.add_child(_paragraph("• " + String(item)))
	return panel


func _populate_static_list(box: VBoxContainer, items: Array) -> void:
	for i in range(box.get_child_count() - 1, 0, -1):
		box.get_child(i).queue_free()
	for item in items:
		box.add_child(_paragraph("• " + String(item)))


func _connect_sim_button(page: Node, node_name: String, filled: bool, callback: Callable) -> void:
	var button := page.get_node("%" + node_name) as Button
	_style_button(button, filled)
	button.pressed.connect(callback)


func _small_metric_card(title: String, body: String, bg: Color, fg: Color) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(190, 108)
	panel.add_theme_stylebox_override("panel", _style(bg, fg, 8, 1))
	var margin := _margin(panel, 14, 12, 14, 12)
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 6)
	margin.add_child(card_box)
	card_box.add_child(_label(title, 15, fg))
	card_box.add_child(_paragraph(body))
	return panel


func _primary_button(text: String, filled: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(120, 42)
	btn.focus_mode = Control.FOCUS_ALL
	_style_button(btn, filled)
	return btn


func _style_button(btn: Button, filled: bool) -> void:
	btn.focus_mode = Control.FOCUS_ALL
	if filled:
		btn.add_theme_stylebox_override("normal", _style(Color("2563eb"), Color("1d4ed8"), 8, 1))
		btn.add_theme_stylebox_override("hover", _style(Color("1d4ed8"), Color("1e40af"), 8, 1))
		btn.add_theme_stylebox_override("pressed", _style(Color("1e40af"), Color("1e3a8a"), 8, 1))
		btn.add_theme_color_override("font_color", Color("ffffff"))
		btn.add_theme_color_override("font_hover_color", Color("ffffff"))
		btn.add_theme_color_override("font_pressed_color", Color("e0e7ff"))
		btn.add_theme_color_override("font_focus_color", Color("ffffff"))
	else:
		btn.add_theme_stylebox_override("normal", _style(Color("ffffff"), Color("bfdbfe"), 8, 1))
		btn.add_theme_stylebox_override("hover", _style(Color("eff6ff"), Color("60a5fa"), 8, 1))
		btn.add_theme_stylebox_override("pressed", _style(Color("dbeafe"), Color("3b82f6"), 8, 1))
		btn.add_theme_color_override("font_color", Color("1d4ed8"))
		btn.add_theme_color_override("font_hover_color", Color("1d4ed8"))
		btn.add_theme_color_override("font_pressed_color", Color("1e40af"))
		btn.add_theme_color_override("font_focus_color", Color("1d4ed8"))


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(Color("ffffff"), Color("d8e4f1"), 8, 1))
	return panel


func _style_panel_node(node: Node) -> void:
	var panel := node as PanelContainer
	if panel:
		panel.add_theme_stylebox_override("panel", _style(Color("ffffff"), Color("d8e4f1"), 8, 1))


func _style(bg: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = bg
	style_box.border_color = border
	style_box.border_width_left = border_width
	style_box.border_width_top = border_width
	style_box.border_width_right = border_width
	style_box.border_width_bottom = border_width
	style_box.corner_radius_top_left = radius
	style_box.corner_radius_top_right = radius
	style_box.corner_radius_bottom_left = radius
	style_box.corner_radius_bottom_right = radius
	style_box.content_margin_left = 12
	style_box.content_margin_right = 12
	style_box.content_margin_top = 6
	style_box.content_margin_bottom = 6
	return style_box


func _margin(parent: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	parent.add_child(margin)
	return margin


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _paragraph(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("475569"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _chip(text: String, bg: Color, fg: Color) -> Label:
	var label := Label.new()
	label.text = "  " + text + "  "
	label.custom_minimum_size = Vector2(0, 28)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", fg)
	label.add_theme_stylebox_override("normal", _style(bg, bg, 8, 0))
	return label


func _clear_content() -> void:
	if content_root == null:
		return
	for child in content_root.get_children():
		child.queue_free()
	board_view = null


## ---- 以下是 guide_system.gd 中保留但不再被 simulation 按钮调用的旧方法 ----
## 保留 _demo_scene 用于兼容性（虽然新逻辑通过 scenario_runner 驱动）

func _demo_piece(piece_type_val: int, rot_val: int, col_val: float, row_val: float) -> Dictionary:
	return {"type": piece_type_val, "rot": rot_val, "col": col_val, "row": row_val}


func _grid_with_piece(grid: Array, piece: Dictionary) -> Array:
	var result := _copy_grid(grid)
	for pos in _piece_cells(int(piece["type"]), int(piece["rot"]), int(round(float(piece["col"]))), int(round(float(piece["row"])))):
		if pos.y >= 0 and pos.y < SIM_ROWS and pos.x >= 0 and pos.x < SIM_COLS:
			result[pos.y][pos.x] = int(piece["type"]) + 1
	return result


func _grid_after_clear(grid: Array) -> Array:
	var result := _copy_grid(grid)
	var new_grid: Array = []
	var cleared := 0
	for grid_row in range(SIM_ROWS):
		var full := true
		for grid_col in range(SIM_COLS):
			if int(result[grid_row][grid_col]) == EMPTY:
				full = false
				break
		if full:
			cleared += 1
		else:
			new_grid.append(result[grid_row])
	for _i in range(cleared):
		new_grid.insert(0, _empty_row())
	return new_grid


func _copy_grid(grid: Array) -> Array:
	var copy: Array = []
	for grid_row in grid:
		copy.append((grid_row as Array).duplicate())
	return copy
