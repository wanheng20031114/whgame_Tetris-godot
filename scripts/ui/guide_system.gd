class_name GuideSystem
extends Control

const BOARD_VIEW_SCENE := preload("res://scripts/ui/guide_board_view.gd")
const SCENARIO_RUNNER := preload("res://scripts/ui/guide_scenario_runner.gd")
const OVERVIEW_PAGE_SCENE := preload("res://scenes/ui/guide/overview_page.tscn")
const BASICS_PAGE_SCENE := preload("res://scenes/ui/guide/basics_page.tscn")
const CHAPTER_PAGE_SCENE := preload("res://scenes/ui/guide/chapter_page.tscn")
const SIMULATION_PAGE_SCENE := preload("res://scenes/ui/guide/simulation_page.tscn")

const EMPTY := 0
const GARBAGE := 8
const SIM_ROWS := 20
const SIM_COLS := 10

## 攻击力表（对战标准）
const ATTACK_TABLE: Array = [
	["Single", "1", "0"],
	["Double", "2", "1"],
	["Triple", "3", "2"],
	["Tetris", "4", "4"],
	["T-Spin Mini", "0", "0"],
	["T-Spin Single", "1", "2"],
	["T-Spin Double", "2", "4"],
	["T-Spin Triple", "3", "6"],
]

## Combo 攻击力加成表
const COMBO_ATTACK_TABLE: Array = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5]

var chapters: Array = []
var basics_chapters: Array = []
var selected_index: int = 0
var content_root: Control
var basics_list: VBoxContainer
var chapters_list: VBoxContainer
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
	if event.is_action_pressed("ui_cancel"):
		if board_view:
			board_view.focused = false
			if board_view is Control:
				(board_view as Control).release_focus()
				get_viewport().set_input_as_handled()
		return
	# 只有棋盘聚焦时才接受输入
	if board_view and not board_view.focused:
		return

	if event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		_sim_move(-1, 0)
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		_sim_move(1, 0)
	elif event.is_action_pressed("soft_drop") or event.is_action_pressed("ui_down"):
		_sim_move(0, 1)
	elif event.is_action_pressed("hard_drop") or event.is_action_pressed("ui_accept"):
		_sim_hard_drop()
	elif event.is_action_pressed("rotate_cw"):
		_sim_rotate(1)
	elif event.is_action_pressed("rotate_ccw"):
		_sim_rotate(-1)
	elif event.is_action_pressed("rotate_180"):
		_sim_rotate(2)
	else:
		return
	get_viewport().set_input_as_handled()


func _build_chapters() -> void:
	basics_chapters = [
		{
			"id": "versus",
			"number": "01",
			"title": "对战俄罗斯方块",
			"tag": "规则",
			"time": "5 分钟",
			"summary": "先理解攻击、垃圾行、攻击条与抵消，这是对战判断的基础。"
		},
		{
			"id": "attack",
			"number": "02",
			"title": "消除造成的攻击力",
			"tag": "数值",
			"time": "5 分钟",
			"summary": "用表格确认 Tetris、T-Spin、B2B、Combo 会带来多少攻击。"
		},
		{
			"id": "technique",
			"number": "03",
			"title": "游戏技巧",
			"tag": "习惯",
			"time": "8 分钟",
			"summary": "整理新手最先该练的通用思路：堆叠、预览、垃圾与操作效率。"
		},
		{
			"id": "replay",
			"number": "04",
			"title": "Replay 复盘与成长",
			"tag": "占位",
			"time": "后续",
			"summary": "后续连接 Replay 系统，说明如何阅读 AI 分析并复盘自己的局。"
		}
	]

	chapters = [
		{
			"id": "wallkick",
			"number": "01",
			"title": tr("TXT_GUIDE_CH1_TITLE"),
			"tag": tr("TXT_GUIDE_CH1_TAG"),
			"time": tr("TXT_GUIDE_CH1_TIME"),
			"summary": tr("TXT_GUIDE_CH1_SUMMARY"),
			"concept": tr("TXT_GUIDE_CH1_CONCEPT"),
			"why": [tr("TXT_GUIDE_CH1_WHY_1"), tr("TXT_GUIDE_CH1_WHY_2"), tr("TXT_GUIDE_CH1_WHY_3")],
			"value": tr("TXT_GUIDE_CH1_VALUE"),
			"steps": [tr("TXT_GUIDE_CH1_STEP_1"), tr("TXT_GUIDE_CH1_STEP_2"), tr("TXT_GUIDE_CH1_STEP_3"), tr("TXT_GUIDE_CH1_STEP_4")],
			"mistakes": [tr("TXT_GUIDE_CH1_ERR_1"), tr("TXT_GUIDE_CH1_ERR_2"), tr("TXT_GUIDE_CH1_ERR_3")],
			"sim": "wallkick"
		},
		{
			"id": "combo",
			"number": "02",
			"title": tr("TXT_GUIDE_CH2_TITLE"),
			"tag": tr("TXT_GUIDE_CH2_TAG"),
			"time": tr("TXT_GUIDE_CH2_TIME"),
			"summary": tr("TXT_GUIDE_CH2_SUMMARY"),
			"concept": tr("TXT_GUIDE_CH2_CONCEPT"),
			"why": [tr("TXT_GUIDE_CH2_WHY_1"), tr("TXT_GUIDE_CH2_WHY_2"), tr("TXT_GUIDE_CH2_WHY_3")],
			"value": tr("TXT_GUIDE_CH2_VALUE"),
			"steps": [tr("TXT_GUIDE_CH2_STEP_1"), tr("TXT_GUIDE_CH2_STEP_2"), tr("TXT_GUIDE_CH2_STEP_3"), tr("TXT_GUIDE_CH2_STEP_4")],
			"mistakes": [tr("TXT_GUIDE_CH2_ERR_1"), tr("TXT_GUIDE_CH2_ERR_2"), tr("TXT_GUIDE_CH2_ERR_3")],
			"sim": "combo"
		},
		{
			"id": "tspin",
			"number": "03",
			"title": tr("TXT_GUIDE_CH3_TITLE"),
			"tag": tr("TXT_GUIDE_CH3_TAG"),
			"time": tr("TXT_GUIDE_CH3_TIME"),
			"summary": tr("TXT_GUIDE_CH3_SUMMARY"),
			"concept": tr("TXT_GUIDE_CH3_CONCEPT"),
			"why": [tr("TXT_GUIDE_CH3_WHY_1"), tr("TXT_GUIDE_CH3_WHY_2"), tr("TXT_GUIDE_CH3_WHY_3")],
			"value": tr("TXT_GUIDE_CH3_VALUE"),
			"steps": [tr("TXT_GUIDE_CH3_STEP_1"), tr("TXT_GUIDE_CH3_STEP_2"), tr("TXT_GUIDE_CH3_STEP_3"), tr("TXT_GUIDE_CH3_STEP_4"), tr("TXT_GUIDE_CH3_STEP_5")],
			"mistakes": [tr("TXT_GUIDE_CH3_ERR_1"), tr("TXT_GUIDE_CH3_ERR_2"), tr("TXT_GUIDE_CH3_ERR_3")],
			"sim": "tspin"
		}
	]


func _build_shell() -> void:
	content_root = %ContentRoot
	basics_list = %BasicsList
	chapters_list = %ChaptersList
	overview_button = %OverviewButton
	_apply_shell_texts()

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


func _apply_shell_texts() -> void:
	var back := %BackButton as Button
	back.text = tr("TXT_GUIDE_BACK")
	overview_button.text = "  " + tr("TXT_GUIDE_OVERVIEW_NAV")
	(get_node("Page/Header/Margin/Row/Tabs/ReadTab") as Label).text = tr("TXT_GUIDE_READ")
	(get_node("Page/Header/Margin/Row/Tabs/DemoTab") as Label).text = tr("TXT_GUIDE_DEMO")
	(get_node("Page/Header/Margin/Row/Tabs/TryTab") as Label).text = tr("TXT_GUIDE_SIM")
	(get_node("Page/BodyMargin/Body/SidebarPanel/SidebarMargin/Sidebar/BasicsSectionLabel") as Label).text = tr("TXT_GUIDE_BASICS")
	(get_node("Page/BodyMargin/Body/SidebarPanel/SidebarMargin/Sidebar/SectionLabel") as Label).text = tr("TXT_GUIDE_CHAPTERS")


func _rebuild_sidebar() -> void:
	for child in basics_list.get_children():
		child.queue_free()
	for child in chapters_list.get_children():
		child.queue_free()

	if overview_button:
		_style_sidebar_button(overview_button, selected_index == -1)

	for i in range(basics_chapters.size()):
		var basics: Dictionary = basics_chapters[i]
		basics_list.add_child(_sidebar_button("%s  %s" % [basics["number"], basics["title"]], _basic_selection(i)))

	for i in range(chapters.size()):
		var chapter: Dictionary = chapters[i]
		chapters_list.add_child(_sidebar_button("%s  %s" % [chapter["number"], chapter["title"]], i))


func _basic_selection(index: int) -> int:
	return -100 - index


func _basic_index_from_selection(value: int) -> int:
	return -100 - value


func _sidebar_button(text: String, index: int) -> Button:
	var btn := Button.new()
	btn.text = "  " + text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 42)
	btn.focus_mode = Control.FOCUS_ALL
	var active := index == selected_index and not in_simulation
	_style_sidebar_button(btn, active)
	if index == -1:
		btn.pressed.connect(_show_overview)
	elif index <= -100:
		btn.pressed.connect(_show_basic_chapter.bind(_basic_index_from_selection(index)))
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
	_style_panel_node(page.get_node("PageMargin/Page/HeroPanel"))
	_style_panel_node(page.get_node("PageMargin/Page/PathPanel"))
	_style_panel_node(page.get_node("PageMargin/Page/CardsPanel"))
	(page.get_node("%HeroTitle") as Label).text = tr("TXT_GUIDE_HERO_TITLE")
	(page.get_node("PageMargin/Page/HeroPanel/HeroMargin/HeroBox/HeroBody") as Label).text = tr("TXT_GUIDE_HERO_BODY")

	var path := page.get_node("%PathBox") as HBoxContainer
	for item in [tr("TXT_GUIDE_BASICS"), "对战机制", "攻击力", "游戏技巧", "Wall Kick", "Combo", "T-Spin Double"]:
		path.add_child(_chip(item, Color("ecfdf5"), Color("047857")))

	var basics_grid := page.get_node("%BasicsGrid") as GridContainer
	(page.get_node("%BasicsTitle") as Label).text = tr("TXT_GUIDE_BASICS")
	for i in range(basics_chapters.size()):
		basics_grid.add_child(_basic_overview_card(i))

	(page.get_node("%LearningTitle") as Label).text = tr("TXT_GUIDE_CHAPTERS")
	var cards_grid := page.get_node("%CardsGrid") as GridContainer
	for i in range(chapters.size()):
		cards_grid.add_child(_chapter_card(i))


func _show_basic_chapter(index: int) -> void:
	in_simulation = false
	selected_index = _basic_selection(index)
	_rebuild_sidebar()
	_clear_content()
	_stop_demo_animation()

	var chapter: Dictionary = basics_chapters[index]
	var page := BASICS_PAGE_SCENE.instantiate()
	content_root.add_child(page)
	_style_panel_node(page.get_node("PageMargin/Page/TitlePanel"))
	(page.get_node("PageMargin/Page/TitlePanel/TitleMargin/TitleBox/Title") as Label).text = "%s %s" % [chapter["number"], chapter["title"]]
	(page.get_node("PageMargin/Page/TitlePanel/TitleMargin/TitleBox/Body") as Label).text = chapter["summary"]
	var host := page.get_node("%ContentHost") as VBoxContainer
	match String(chapter["id"]):
		"versus":
			host.add_child(_versus_tetris_section(false))
		"attack":
			host.add_child(_attack_table())
		"technique":
			host.add_child(_general_technique_section(false))
		_:
			host.add_child(_basics_placeholder_section())


func _basic_overview_card(index: int) -> Control:
	var chapter: Dictionary = basics_chapters[index]
	var card := _panel()
	card.custom_minimum_size = Vector2(360, 150)
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
	box.add_child(_label("%s %s" % [tr("TXT_GUIDE_ESTIMATE_PREFIX"), String(chapter["time"])], 13, Color("64748b")))

	var read_btn := _primary_button(tr("TXT_GUIDE_VIEW"), false)
	read_btn.pressed.connect(_show_basic_chapter.bind(index))
	box.add_child(read_btn)
	return card


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
	box.add_child(_label("%s %s" % [tr("TXT_GUIDE_ESTIMATE_PREFIX"), String(chapter["time"])], 13, Color("64748b")))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	var read_btn := _primary_button(tr("TXT_GUIDE_VIEW"), false)
	read_btn.pressed.connect(_show_chapter.bind(index))
	buttons.add_child(read_btn)
	var sim_btn := _primary_button(tr("TXT_GUIDE_START_SIM"), true)
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
	_style_panel_node(page.get_node("ArticleScroll/ArticleMargin/Article/TitlePanel"))
	_style_panel_node(page.get_node("ArticleScroll/ArticleMargin/Article/ConceptSection"))
	_style_panel_node(page.get_node("ArticleScroll/ArticleMargin/Article/WhySection"))
	_style_panel_node(page.get_node("ArticleScroll/ArticleMargin/Article/ValueSection"))
	_style_panel_node(page.get_node("ArticleScroll/ArticleMargin/Article/StepsSection"))
	_style_panel_node(page.get_node("ArticleScroll/ArticleMargin/Article/MistakesSection"))
	_style_panel_node(page.get_node("DemoPanel"))

	var chip := page.get_node("%Chip") as Label
	chip.text = "  %s / %s / %s  " % [chapter["number"], chapter["tag"], chapter["time"]]
	chip.add_theme_stylebox_override("normal", _style(Color("e0f2fe"), Color("e0f2fe"), 8, 0))
	(page.get_node("ArticleScroll/ArticleMargin/Article/ConceptSection/ConceptMargin/ConceptBox/ConceptTitle") as Label).text = tr("TXT_GUIDE_CONCEPT")
	(page.get_node("ArticleScroll/ArticleMargin/Article/WhySection/WhyMargin/WhyBox/WhyTitle") as Label).text = tr("TXT_GUIDE_WHY")
	(page.get_node("ArticleScroll/ArticleMargin/Article/ValueSection/ValueMargin/ValueBox/ValueTitle") as Label).text = tr("TXT_GUIDE_VALUE")
	(page.get_node("ArticleScroll/ArticleMargin/Article/StepsSection/StepsMargin/StepsBox/StepsTitle") as Label).text = tr("TXT_GUIDE_STEPS")
	(page.get_node("ArticleScroll/ArticleMargin/Article/MistakesSection/MistakesMargin/MistakesBox/MistakesTitle") as Label).text = tr("TXT_GUIDE_MISTAKES")
	(page.get_node("DemoPanel/DemoMargin/DemoBox/DemoTitle") as Label).text = tr("TXT_GUIDE_DEMO_TITLE")
	(page.get_node("%Title") as Label).text = chapter["title"]
	(page.get_node("%Summary") as Label).text = chapter["summary"]
	(page.get_node("%ConceptText") as Label).text = chapter["concept"]
	(page.get_node("%ValueText") as Label).text = chapter["value"]

	_populate_static_list(page.get_node("%WhyBox") as VBoxContainer, chapter["why"])
	_populate_static_list(page.get_node("%StepsBox") as VBoxContainer, chapter["steps"])
	_populate_static_list(page.get_node("%MistakesBox") as VBoxContainer, chapter["mistakes"])

	var sim_btn := page.get_node("%SimButton") as Button
	sim_btn.text = tr("TXT_GUIDE_ENTER_SIM")
	_style_button(sim_btn, true)
	sim_btn.pressed.connect(_start_simulation.bind(chapter["sim"], index))
	var prev_btn := page.get_node("%PrevButton") as Button
	prev_btn.text = tr("TXT_GUIDE_PREV_CH")
	_style_button(prev_btn, false)
	prev_btn.disabled = index <= 0
	prev_btn.pressed.connect(_show_chapter.bind(index - 1))
	var next_btn := page.get_node("%NextButton") as Button
	next_btn.text = tr("TXT_GUIDE_NEXT_CH")
	_style_button(next_btn, false)
	next_btn.disabled = index >= chapters.size() - 1
	next_btn.pressed.connect(_show_chapter.bind(index + 1))

	demo_action_label = page.get_node("%ActionLabel") as Label
	demo_action_label.text = tr("TXT_GUIDE_READY")
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

	demo_tween.tween_callback(_set_demo_action.bind(tr("TXT_GUIDE_LOCKED")))
	demo_tween.tween_callback(func(): board_view.set_state(demo["locked_grid"], {}, targets, demo["rows"], []))

	# 播放消行特效
	if not (demo["rows"] as Array).is_empty():
		demo_tween.tween_callback(func():
			if board_view:
				board_view.play_clear_effect(demo["rows"])
		)

	demo_tween.tween_interval(0.22)
	demo_tween.tween_callback(_set_demo_action.bind(tr("TXT_GUIDE_CLEAR")))
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
			{"op": "rotate", "direction": 1, "label": tr("TXT_GUIDE_OP_ROT_CW_ENTRY")},
			{"op": "drop_to", "row": 18, "label": tr("TXT_GUIDE_OP_DROP_SLOT")},
			{"op": "rotate", "direction": 1, "label": tr("TXT_GUIDE_OP_ROT_CW_TSPIN")}
		]
	if scene_id == "wallkick":
		return [
			{"op": "rotate", "direction": -1, "label": tr("TXT_GUIDE_OP_ROT_CCW")},
			{"op": "move", "dx": 1, "count": 3, "label": tr("TXT_GUIDE_OP_MOVE_RIGHT_WALL")},
			{"op": "wait", "duration": 1.0, "label": tr("TXT_GUIDE_OP_WAIT_WALL")},
			{"op": "rotate", "direction": 1, "label": tr("TXT_GUIDE_OP_ROT_KICK_L")},
			{"op": "wait", "duration": 1.5, "label": tr("TXT_GUIDE_OP_OBSERVE_KICK")},
			{"op": "rotate", "direction": -1, "label": tr("TXT_GUIDE_OP_ROT_CCW_AGAIN")},
			{"op": "move", "dx": 1, "count": 1, "label": tr("TXT_GUIDE_OP_MOVE_RIGHT_WALL_AGAIN")},
			{"op": "hard_drop", "label": tr("TXT_GUIDE_OP_HARD_DROP")},
			{"op": "wait", "duration": 1.0, "label": tr("TXT_GUIDE_OP_WAIT_SPIN")},
			{"op": "rotate", "direction": 1, "label": tr("TXT_GUIDE_OP_ROT_LSPIN")}
		]
	if scene_id == "combo":
		# O 方块直接硬降到右侧 2 列
		return [
			{"op": "move", "dx": 1, "count": 1, "label": tr("TXT_GUIDE_OP_MOVE_RIGHT")},
			{"op": "drop_to", "row": 19, "label": tr("TXT_GUIDE_OP_DROP_CLEAR2")}
		]
	# tetris
	return [
		{"op": "drop_to", "row": 8, "label": tr("TXT_GUIDE_OP_SOFT_DROP")},
		{"op": "move", "dx": 1, "count": 3, "label": tr("TXT_GUIDE_OP_MOVE_RIGHT_WELL")},
		{"op": "rotate", "direction": 1, "label": tr("TXT_GUIDE_OP_ROT_CW_90")},
		{"op": "move", "dx": 1, "count": 1, "label": tr("TXT_GUIDE_OP_MOVE_WELL_EDGE")},
		{"op": "drop_to", "row": 17, "label": tr("TXT_GUIDE_OP_DROP_WELL")}
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
	(page.get_node("%FocusHint") as Label).text = tr("TXT_GUIDE_SIM_HINT")
	(page.get_node("%ResetButton") as Button).text = tr("TXT_GUIDE_RESET")
	(page.get_node("%ExitButton") as Button).text = tr("TXT_GUIDE_EXIT_SIM")

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
			_set_feedback(tr("TXT_GUIDE_OBJ_TSPIN"))
		"combo":
			_set_feedback(tr("TXT_GUIDE_OBJ_COMBO"))
		"wallkick":
			_set_feedback(tr("TXT_GUIDE_OBJ_WALLKICK"))
		_:
			_set_feedback(tr("TXT_GUIDE_OBJ_TETRIS"))

	_update_objective()
	_refresh_sim_view()
	_focus_sim_board()


func _focus_sim_board() -> void:
	if board_view == null:
		return
	board_view.focused = true
	if board_view is Control:
		(board_view as Control).call_deferred("grab_focus")


func _update_objective() -> void:
	if objective_label == null:
		return
	match sim_id:
		"tspin":
			objective_label.text = tr("TXT_GUIDE_SIM_TSPIN")
		"combo":
			objective_label.text = tr("TXT_GUIDE_SIM_COMBO") % sim_combo
		"wallkick":
			objective_label.text = tr("TXT_GUIDE_SIM_WALLKICK")
		_:
			objective_label.text = tr("TXT_GUIDE_SIM_TETRIS")


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
	_set_feedback(tr("TXT_GUIDE_ERR_ROT"), false, true)


func _sim_hard_drop() -> void:
	if sim_success or sim_locked or scenario_runner == null:
		return
	scenario_runner.hard_drop()
	_lock_sim_piece()


func _sim_lock_now() -> void:
	if sim_success or sim_locked or scenario_runner == null:
		return
	if scenario_runner.is_valid(scenario_runner.piece_type, scenario_runner.rot, scenario_runner.col, scenario_runner.row + 1):
		_set_feedback(tr("TXT_GUIDE_ERR_LOCK"), false, true)
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
				_set_feedback(tr("TXT_GUIDE_SUC_TSPIN") % elapsed, true)
			elif scenario_runner.piece_type == PieceData.Type.T and bool(result["spin"]) and cleared == 1:
				sim_locked = true
				_set_feedback(tr("TXT_GUIDE_ERR_TSPIN_1"), false, true)
			else:
				sim_locked = true
				_set_feedback(tr("TXT_GUIDE_ERR_TSPIN_0"), false, true)
		"combo":
			if cleared > 0:
				sim_combo += 1
				if sim_combo >= 5:
					sim_success = true
					sim_locked = true
					_set_feedback(tr("TXT_GUIDE_SUC_COMBO") % elapsed, true)
				else:
					var extra: int = int(COMBO_ATTACK_TABLE[mini(sim_combo, COMBO_ATTACK_TABLE.size() - 1)])
					_set_feedback(tr("TXT_GUIDE_SUC_COMBO_N") % [sim_combo, extra], true)
					sim_sequence_index += 1
					scenario_runner.phase = sim_sequence_index
					scenario_runner.spawn(PieceData.Type.O, 7, 2, PieceData.RotationState.SPAWN)
					sim_locked = false
			else:
				sim_combo = 0
				sim_locked = true
				_set_feedback(tr("TXT_GUIDE_ERR_COMBO"), false, true)
		"wallkick":
			sim_locked = true
			if bool(result["spin"]) and cleared >= 2:
				sim_success = true
				_set_feedback(tr("TXT_GUIDE_SUC_LSPIN"), true)
			else:
				_set_feedback(tr("TXT_GUIDE_ERR_LSPIN"), false, true)
		_:
			if scenario_runner.piece_type == PieceData.Type.I and cleared == 4:
				sim_success = true
				sim_locked = true
				_set_feedback(tr("TXT_GUIDE_SUC_TETRIS") % elapsed, true)
			else:
				sim_locked = true
				_set_feedback(tr("TXT_GUIDE_ERR_TETRIS"), false, true)

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


func _versus_tetris_section(show_title: bool = true) -> Control:
	var panel := _panel()
	var margin := _margin(panel, 20, 18, 20, 18)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	if show_title:
		box.add_child(_label("01 对战俄罗斯方块", 22, Color("0f1f45")))
	box.add_child(_paragraph("对战的目标不是单纯消行，而是在保证自己不被顶出场地的同时，把攻击转化为对手需要处理的垃圾行。你打出的攻击越高，对手的攻击条压力越大；对手打来的攻击也会先进入你的攻击条，随后变成垃圾行进入棋盘。"))
	box.add_child(_paragraph("因此，对战中的每一步都要同时考虑两件事：这一手能不能制造攻击，以及这一手能不能处理即将到来的垃圾。很多时候，先用消行抵消攻击，比继续堆高准备大招更安全。"))

	box.add_child(_list_section("阅读攻击条时先看三件事", [
		"攻击条越高，下一次不消行锁定时越危险。",
		"如果当前地形已经很高，优先考虑清线和抵消垃圾。",
		"如果攻击条压力较低，可以继续准备 Tetris、T-Spin 或 Combo。"
	]))
	return panel


func _general_technique_section(show_title: bool = true) -> Control:
	var panel := _panel()
	var margin := _margin(panel, 20, 18, 20, 18)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	if show_title:
		box.add_child(_label("03 游戏技巧", 22, Color("0f1f45")))
	box.add_child(_paragraph("这些不是固定开局，也不是必须背下来的答案，而是适合现代俄罗斯方块的通用判断方式。新手先掌握这些习惯，再进入具体的 Tetris、Combo 和 T-Spin 教学，会更容易理解为什么要这样摆。"))
	box.add_child(_list_section("多堆高价值消除", [
		"不要只看到能消 1 行就立刻清掉。很多时候，保留结构等待 Tetris 或 T-Spin，会带来更高攻击。",
		"如果地形危险，先清线保命；如果地形稳定，就可以主动准备高价值消除。"
	]))
	box.add_child(_list_section("留心垃圾与攻击条", [
		"对战中存活是第一目标。攻击条明显升高时，先想办法抵消或降低地形。",
		"不要在垃圾即将进入时继续盲目堆高。能安全清线，往往比强行做大攻击更好。"
	]))
	box.add_child(_list_section("阅读 Next 预览", [
		"本项目会显示 5 个 Next。新手至少先看当前块和下一个块，再逐渐练习用余光看更多。",
		"看到后续有 I、T、S/Z 时，可以提前决定井、T 槽或表面形状，减少临时补救。"
	]))
	box.add_child(_list_section("保持可继续操作的堆叠", [
		"平整的地形更容易处理垃圾，但过于平坦也会让 S/Z 这类方块难摆。",
		"好的堆叠不是完全平，而是保留能接住下一批方块的形状。"
	]))
	box.add_child(_list_section("减少不必要的软降", [
		"硬降更快，软降会增加操作时间和按键数。",
		"T-Spin 等技巧确实需要软降，但普通堆叠时应尽量减少长距离软降。"
	]))
	return panel


func _basics_placeholder_section() -> Control:
	return _text_section(
		"04 Replay 复盘与成长",
		"这一章后续连接 Replay 系统：解释如何查看自己的消行、攻击、Combo、T-Spin、地形风险与 AI 建议。当前先保留位置，等 Replay 的 Guide 文案定稿后再展开。"
	)


func _attack_table() -> Control:
	var panel := _panel()
	var margin := _margin(panel, 20, 18, 20, 18)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	# 标题
	box.add_child(_label(tr("TXT_GUIDE_ATK_TITLE"), 22, Color("0f1f45")))
	box.add_child(_paragraph(tr("TXT_GUIDE_ATK_DESC")))

	# 攻击力表格
	var table_grid := GridContainer.new()
	table_grid.columns = 3
	table_grid.add_theme_constant_override("h_separation", 6)
	table_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(table_grid)

	# 表头
	var headers := [tr("TXT_GUIDE_ATK_H1"), tr("TXT_GUIDE_ATK_H2"), tr("TXT_GUIDE_ATK_H3")]
	for header_index in range(3):
		var header_text: String = headers[header_index]
		var header := _label(header_text, 14, Color("ffffff"))
		header.custom_minimum_size = Vector2(170 if header_index == 0 else 120, 32)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		header.autowrap_mode = TextServer.AUTOWRAP_OFF
		header.add_theme_stylebox_override("normal", _style(Color("1d4ed8"), Color("1d4ed8"), 4, 0))
		table_grid.add_child(header)

	# 数据行
	for row_data in ATTACK_TABLE:
		var is_high := int(row_data[2]) >= 4
		var bg := Color("fef3c7") if is_high else Color("f8fafc")
		for cell_idx in range(3):
			var cell_label := _label(row_data[cell_idx], 14, Color("1e293b"))
			cell_label.custom_minimum_size = Vector2(170 if cell_idx == 0 else 120, 30)
			cell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			cell_label.add_theme_stylebox_override("normal", _style(bg, Color("e2e8f0"), 2, 1))
			table_grid.add_child(cell_label)

	# B2B 说明
	var b2b_panel := _panel()
	b2b_panel.add_theme_stylebox_override("panel", _style(Color("eff6ff"), Color("93c5fd"), 8, 1))
	var b2b_margin := _margin(b2b_panel, 14, 10, 14, 10)
	var b2b_box := VBoxContainer.new()
	b2b_box.add_theme_constant_override("separation", 4)
	b2b_margin.add_child(b2b_box)
	b2b_box.add_child(_label(tr("TXT_GUIDE_B2B_TITLE"), 15, Color("1d4ed8")))
	b2b_box.add_child(_paragraph(tr("TXT_GUIDE_B2B_DESC")))
	box.add_child(b2b_panel)

	# Combo 说明
	var combo_panel := _panel()
	combo_panel.add_theme_stylebox_override("panel", _style(Color("ecfdf5"), Color("86efac"), 8, 1))
	var combo_margin := _margin(combo_panel, 14, 10, 14, 10)
	var combo_box := VBoxContainer.new()
	combo_box.add_theme_constant_override("separation", 4)
	combo_margin.add_child(combo_box)
	combo_box.add_child(_label(tr("TXT_GUIDE_COMBO_TITLE"), 15, Color("047857")))
	combo_box.add_child(_paragraph(tr("TXT_GUIDE_COMBO_DESC1")))
	combo_box.add_child(_paragraph(tr("TXT_GUIDE_COMBO_DESC2")))
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
