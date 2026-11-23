class_name GuideSystem
extends Control

const SCENARIO_RUNNER := preload("res://scripts/ui/guide_scenario_runner.gd")
const OVERVIEW_PAGE_SCENE := preload("res://scenes/ui/guide/overview_page.tscn")
const BASICS_PAGE_SCENE := preload("res://scenes/ui/guide/basics_page.tscn")
const CHAPTER_PAGE_SCENE := preload("res://scenes/ui/guide/chapter_page.tscn")
const SIMULATION_PAGE_SCENE := preload("res://scenes/ui/guide/simulation_page.tscn")

## 棋盘获得焦点时先匹配玩家的游戏键位，再匹配导航键。
const SIMULATION_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"soft_drop", &"hard_drop", &"rotate_cw", &"rotate_ccw", &"rotate_180",
	&"ui_left", &"ui_right", &"ui_down", &"ui_accept", &"ui_cancel",
]

## 攻击力表（对战标准）
const ATTACK_TABLE: Array = [
	["Single", "1", "0"],
	["Double", "2", "1"],
	["Triple", "3", "2"],
	["Tetris", "4", "4"],
	["T-Spin Single", "1", "2"],
	["T-Spin Double", "2", "4"],
	["T-Spin Triple", "3", "6"],
]

## Combo 攻击力加成表
const COMBO_ATTACK_TABLE: Array = [0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5]

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
var demo_tween: Tween
var demo_action_label: Label
var demo_step: int = 0
var in_simulation: bool = false

var sim_id: String = ""
var sim_sequence_index: int = 0
var sim_combo: int = 0
var sim_attempts: int = 0
var sim_success: bool = false
var sim_started_msec: int = 0
var sim_hint_visible: bool = true
var sim_locked: bool = false
var scenario_runner: RefCounted
var _feedback_key: String = ""
var _feedback_args: Array = []
var _feedback_success: bool = false
var _feedback_danger: bool = false


func _ready() -> void:
	_build_chapters()
	_build_shell()
	_show_overview()
	UITheme.theme_changed.connect(_on_theme_changed)


## 代码生成的样式取自调色板，切换主题时重建当前页面
func _on_theme_changed(_mode: String) -> void:
	_build_shell_styles()
	if in_simulation:
		_rebuild_sidebar()
		_refresh_sim_texts()
	elif selected_index == -1:
		_show_overview()
	elif selected_index <= -100:
		_show_basic_chapter(_basic_index_from_selection(selected_index))
	else:
		_show_chapter(selected_index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_build_chapters()
		_apply_shell_texts()
		_on_theme_changed(UITheme.mode)
	if what == NOTIFICATION_RESIZED and is_inside_tree() and board_view:
		board_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if not in_simulation or not board_view.has_focus():
		return

	for action in SIMULATION_ACTIONS:
		if not event.is_action_pressed(action):
			continue
		match action:
			&"move_left", &"ui_left": _sim_move(-1, 0)
			&"move_right", &"ui_right": _sim_move(1, 0)
			&"soft_drop", &"ui_down": _sim_move(0, 1)
			&"hard_drop", &"ui_accept": _sim_hard_drop()
			&"rotate_cw": _sim_rotate(1)
			&"rotate_ccw": _sim_rotate(-1)
			&"rotate_180": _sim_rotate(2)
			&"ui_cancel": board_view.release_focus()
		get_viewport().set_input_as_handled()
		return


func _build_chapters() -> void:
	basics_chapters = [
		{
			"id": "versus",
			"number": "01",
			"title": tr("TXT_GUIDE_BASIC_VERSUS_TITLE"),
			"tag": tr("TXT_GUIDE_BASIC_VERSUS_TAG"),
			"time": tr("TXT_GUIDE_BASIC_VERSUS_TIME"),
			"summary": tr("TXT_GUIDE_BASIC_VERSUS_SUMMARY")
		},
		{
			"id": "attack",
			"number": "02",
			"title": tr("TXT_GUIDE_BASIC_ATTACK_TITLE"),
			"tag": tr("TXT_GUIDE_BASIC_ATTACK_TAG"),
			"time": tr("TXT_GUIDE_BASIC_ATTACK_TIME"),
			"summary": tr("TXT_GUIDE_BASIC_ATTACK_SUMMARY")
		},
		{
			"id": "technique",
			"number": "03",
			"title": tr("TXT_GUIDE_BASIC_TECH_TITLE"),
			"tag": tr("TXT_GUIDE_BASIC_TECH_TAG"),
			"time": tr("TXT_GUIDE_BASIC_TECH_TIME"),
			"summary": tr("TXT_GUIDE_BASIC_TECH_SUMMARY")
		},
		{
			"id": "replay",
			"number": "04",
			"title": tr("TXT_GUIDE_BASIC_REPLAY_TITLE"),
			"tag": tr("TXT_GUIDE_BASIC_REPLAY_TAG"),
			"time": tr("TXT_GUIDE_BASIC_REPLAY_TIME"),
			"summary": tr("TXT_GUIDE_BASIC_REPLAY_SUMMARY")
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

	_build_shell_styles()
	var back := %BackButton as Button
	back.pressed.connect(func(): UITheme.goto_scene("res://scenes/ui/main.tscn"))

	overview_button.pressed.connect(_show_overview)

	_rebuild_sidebar()




func _build_shell_styles() -> void:
	var header := get_node_or_null("Page/Header") as PanelContainer
	if header:
		header.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var sidebar_panel := get_node_or_null("Page/BodyMargin/Body/SidebarPanel") as PanelContainer
	if sidebar_panel:
		sidebar_panel.theme_type_variation = &"GlassPanel"
	# 阅读 → 演示 → 模拟：彩色步骤条
	var tabs := get_node_or_null("Page/Header/Margin/Row/Tabs") as HBoxContainer
	if tabs:
		tabs.add_theme_constant_override("separation", 6)
		for child in tabs.get_children():
			if child.has_meta(&"step_arrow"):
				child.queue_free()
		var names := ["ReadTab", "DemoTab", "TryTab"]
		for i in names.size():
			var tab := tabs.get_node(names[i]) as Label
			var chip := _hue_chip("", _hue(i))
			tab.add_theme_stylebox_override("normal", chip.get_theme_stylebox("normal"))
			tab.add_theme_color_override("font_color", chip.get_theme_color("font_color"))
			tab.add_theme_font_size_override("font_size", 13)
			tab.custom_minimum_size = Vector2(0, 30)
			tab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			chip.free()
			if i > 0:
				var arrow := _label("›", 18, _c("faint"))
				arrow.autowrap_mode = TextServer.AUTOWRAP_OFF
				arrow.set_meta(&"step_arrow", true)
				tabs.add_child(arrow)
				tabs.move_child(arrow, tab.get_index())
	if overview_button:
		_style_sidebar_button(overview_button, selected_index == -1 and not in_simulation)


func _apply_shell_texts() -> void:
	var back := %BackButton as Button
	back.text = tr("TXT_GUIDE_BACK")
	overview_button.text = tr("TXT_GUIDE_OVERVIEW_NAV")
	(get_node("Page/Header/Margin/Row/Tabs/ReadTab") as Label).text = "  1  %s  " % tr("TXT_GUIDE_READ")
	(get_node("Page/Header/Margin/Row/Tabs/DemoTab") as Label).text = "  2  %s  " % tr("TXT_GUIDE_DEMO")
	(get_node("Page/Header/Margin/Row/Tabs/TryTab") as Label).text = "  3  %s  " % tr("TXT_GUIDE_SIM")
	(%BasicsSectionLabel as Label).text = tr("TXT_GUIDE_BASICS")
	(%SectionLabel as Label).text = tr("TXT_GUIDE_CHAPTERS")


func _rebuild_sidebar() -> void:
	for child in basics_list.get_children():
		basics_list.remove_child(child)
		child.queue_free()
	for child in chapters_list.get_children():
		chapters_list.remove_child(child)
		child.queue_free()

	if overview_button:
		_style_sidebar_button(overview_button, selected_index == -1)

	for i in range(basics_chapters.size()):
		var basics: Dictionary = basics_chapters[i]
		basics_list.add_child(_sidebar_button("%s  %s" % [basics["number"], basics["title"]], _basic_selection(i), _hue(i)))

	for i in range(chapters.size()):
		var chapter: Dictionary = chapters[i]
		chapters_list.add_child(_sidebar_button("%s  %s" % [chapter["number"], chapter["title"]], i, _hue(i + basics_chapters.size())))


func _basic_selection(index: int) -> int:
	return -100 - index


func _basic_index_from_selection(value: int) -> int:
	return -100 - value


func _sidebar_button(text: String, index: int, hue: String = "accent") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 42)
	btn.focus_mode = Control.FOCUS_ALL
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var active := index == selected_index and not in_simulation
	_style_sidebar_button(btn, active, hue)
	if index == -1:
		btn.pressed.connect(_show_overview)
	elif index <= -100:
		btn.pressed.connect(_show_basic_chapter.bind(_basic_index_from_selection(index)))
	else:
		btn.pressed.connect(_show_chapter.bind(index))
	return btn


func _style_sidebar_button(btn: Button, active: bool, hue: String = "accent") -> void:
	btn.theme_type_variation = &"NavButton"
	for key in ["normal", "hover", "pressed", "focus"]:
		btn.remove_theme_stylebox_override(key)
	for key in ["font_color", "font_hover_color", "font_focus_color"]:
		btn.remove_theme_color_override(key)
	btn.set_meta(&"nav_hue", hue)
	if active:
		# 选中项：章节色柔底 + 左侧色条
		var col := _c(hue)
		var box := _style(col, col, 99, 0)
		box.content_margin_left = 18
		box.content_margin_top = 10
		box.content_margin_bottom = 10
		btn.add_theme_stylebox_override("normal", box)
		btn.add_theme_stylebox_override("hover", box)
		var fg := _c("ink") if UITheme.is_dark() else Color.WHITE
		btn.add_theme_color_override("font_color", fg)
		btn.add_theme_color_override("font_hover_color", fg)
		btn.add_theme_color_override("font_focus_color", fg)


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

	_flatten_panel(page.get_node("PageMargin/Page/PathPanel"))
	_flatten_panel(page.get_node("PageMargin/Page/CardsPanel"))
	var path := page.get_node("%PathBox") as HFlowContainer
	var steps := [tr("TXT_GUIDE_BASICS"), tr("TXT_GUIDE_PATH_VERSUS"), tr("TXT_GUIDE_PATH_ATTACK"), tr("TXT_GUIDE_PATH_TECHNIQUE"), "Wall Kick", "Combo", "T-Spin Double"]
	for i in steps.size():
		if i > 0:
			var arrow := _label("›", 18, _c("faint"))
			arrow.autowrap_mode = TextServer.AUTOWRAP_OFF
			path.add_child(arrow)
		path.add_child(_hue_chip(steps[i], _hue(i)))

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
	var hue := _hue(index)
	var card := _hue_card(int(String(chapter["number"])), hue)
	card.custom_minimum_size = Vector2(320, 150)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	var title := _label(chapter["title"], 20, _c("text"))
	title.add_theme_font_override("font", get_theme_font("font", "HeaderLabel"))
	title.add_theme_stylebox_override("normal", _badge_indent())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_hue_chip(chapter["tag"], hue))

	box.add_child(_paragraph(chapter["summary"]))
	box.add_child(_label("%s %s" % [tr("TXT_GUIDE_ESTIMATE_PREFIX"), String(chapter["time"])], 13, _c("muted")))

	var read_btn := _primary_button(tr("TXT_GUIDE_VIEW"), false)
	read_btn.pressed.connect(_show_basic_chapter.bind(index))
	box.add_child(read_btn)
	return card


func _chapter_card(index: int) -> Control:
	var chapter: Dictionary = chapters[index]
	var hue := _hue(index + basics_chapters.size())
	var card := _hue_card(int(String(chapter["number"])), hue)
	card.custom_minimum_size = Vector2(320, 170)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	var title := _label(chapter["title"], 20, _c("text"))
	title.add_theme_font_override("font", get_theme_font("font", "HeaderLabel"))
	title.add_theme_stylebox_override("normal", _badge_indent())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_hue_chip(chapter["tag"], hue))

	box.add_child(_paragraph(chapter["summary"]))
	box.add_child(_label("%s %s" % [tr("TXT_GUIDE_ESTIMATE_PREFIX"), String(chapter["time"])], 13, _c("muted")))

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
	chip.add_theme_stylebox_override("normal", _style(_soft("accent", 0.14), _soft("accent", 0.14), 8, 0))
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
	demo_action_label.add_theme_stylebox_override("normal", _style(_soft("success", 0.12), _soft("success", 0.35), 8, 1))
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
	if from_piece.rot != to_piece.rot:
		# 踢墙的位置和朝向是一次操作。用两个合法姿态叠化，避免把旧朝向画在新坐标上。
		var after_turn := value >= 0.5
		board_view.set_state(grid, to_piece if after_turn else from_piece, targets, rows, focus)
		board_view.blend_turn_pose(from_piece if after_turn else to_piece, 1.0 - value if after_turn else value)
		return
	var piece := from_piece.duplicate()
	piece.col = lerpf(from_piece.col, to_piece.col, value)
	piece.row = lerpf(from_piece.row, to_piece.row, value)
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
	sim_sequence_index = 0
	sim_combo = -1
	sim_attempts = 0
	sim_success = false
	sim_locked = false
	sim_hint_visible = true
	sim_started_msec = Time.get_ticks_msec()

	match sim_id:
		"tspin":
			_set_feedback("TXT_GUIDE_OBJ_TSPIN")
		"combo":
			_set_feedback("TXT_GUIDE_OBJ_COMBO")
		"wallkick":
			_set_feedback("TXT_GUIDE_OBJ_WALLKICK")
		_:
			_set_feedback("TXT_GUIDE_OBJ_TETRIS")

	_update_objective()
	_refresh_sim_view()
	board_view.grab_focus()


func _update_objective() -> void:
	if objective_label == null:
		return
	match sim_id:
		"tspin":
			objective_label.text = tr("TXT_GUIDE_SIM_TSPIN")
		"combo":
			objective_label.text = tr("TXT_GUIDE_SIM_COMBO") % maxi(sim_combo, 0)
		"wallkick":
			objective_label.text = tr("TXT_GUIDE_SIM_WALLKICK")
		_:
			objective_label.text = tr("TXT_GUIDE_SIM_TETRIS")


func _refresh_sim_texts() -> void:
	var page := content_root.get_child(0)
	(page.get_node("%FocusHint") as Label).text = tr("TXT_GUIDE_SIM_HINT")
	(page.get_node("%ResetButton") as Button).text = tr("TXT_GUIDE_RESET")
	(page.get_node("%ExitButton") as Button).text = tr("TXT_GUIDE_EXIT_SIM")
	_update_objective()
	_set_feedback(_feedback_key, _feedback_success, _feedback_danger, _feedback_args)


func _set_feedback(key: String, success: bool = false, danger: bool = false, args: Array = []) -> void:
	_feedback_key = key
	_feedback_args = args
	_feedback_success = success
	_feedback_danger = danger
	if feedback_label == null:
		return
	feedback_label.text = tr(key) if args.is_empty() else tr(key) % args
	if success:
		feedback_label.add_theme_color_override("font_color", _c("success"))
	elif danger:
		feedback_label.add_theme_color_override("font_color", _c("warning"))
	else:
		feedback_label.add_theme_color_override("font_color", _c("muted"))


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
	_set_feedback("TXT_GUIDE_ERR_ROT", false, true)


func _sim_hard_drop() -> void:
	if sim_success or sim_locked or scenario_runner == null:
		return
	scenario_runner.hard_drop()
	_lock_sim_piece()


func _sim_lock_now() -> void:
	if sim_success or sim_locked or scenario_runner == null:
		return
	if scenario_runner.is_valid(scenario_runner.piece_type, scenario_runner.rot, scenario_runner.col, scenario_runner.row + 1):
		_set_feedback("TXT_GUIDE_ERR_LOCK", false, true)
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
				_set_feedback("TXT_GUIDE_SUC_TSPIN", true, false, [elapsed])
			elif scenario_runner.piece_type == PieceData.Type.T and bool(result["spin"]) and cleared == 1:
				sim_locked = true
				_set_feedback("TXT_GUIDE_ERR_TSPIN_1", false, true)
			else:
				sim_locked = true
				_set_feedback("TXT_GUIDE_ERR_TSPIN_0", false, true)
		"combo":
			if cleared > 0:
				sim_combo += 1
				if sim_combo >= 4:
					sim_success = true
					sim_locked = true
					_set_feedback("TXT_GUIDE_SUC_COMBO", true, false, [elapsed])
				else:
					var extra: int = int(COMBO_ATTACK_TABLE[mini(sim_combo, COMBO_ATTACK_TABLE.size() - 1)])
					_set_feedback("TXT_GUIDE_SUC_COMBO_N", true, false, [sim_combo, extra])
					sim_sequence_index += 1
					scenario_runner.phase = sim_sequence_index
					scenario_runner.spawn(PieceData.Type.O, 7, 2, PieceData.RotationState.SPAWN)
					sim_locked = false
			else:
				sim_combo = 0
				sim_locked = true
				_set_feedback("TXT_GUIDE_ERR_COMBO", false, true)
		"wallkick":
			sim_locked = true
			if bool(result["spin"]) and cleared >= 2:
				sim_success = true
				_set_feedback("TXT_GUIDE_SUC_LSPIN", true)
			else:
				_set_feedback("TXT_GUIDE_ERR_LSPIN", false, true)
		_:
			if scenario_runner.piece_type == PieceData.Type.I and cleared == 4:
				sim_success = true
				sim_locked = true
				_set_feedback("TXT_GUIDE_SUC_TETRIS", true, false, [elapsed])
			else:
				sim_locked = true
				_set_feedback("TXT_GUIDE_ERR_TETRIS", false, true)

	_update_objective()
	_refresh_sim_view()


func _refresh_sim_view() -> void:
	if board_view == null or scenario_runner == null:
		return
	board_view.set_state(
		scenario_runner.grid,
		{} if sim_locked else scenario_runner.piece_dict(),
		scenario_runner.target_cells() if sim_hint_visible else [],
		scenario_runner.highlight_rows(),
		scenario_runner.focus_cells()
	)


func _versus_tetris_section(show_title: bool = true) -> Control:
	var panel := _panel()
	var margin := _margin(panel, 20, 18, 20, 18)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	if show_title:
		box.add_child(_label(tr("TXT_GUIDE_VERSUS_TITLE"), 22, _c("text")))
	box.add_child(_paragraph(tr("TXT_GUIDE_VERSUS_BODY_1")))
	box.add_child(_paragraph(tr("TXT_GUIDE_VERSUS_BODY_2")))

	box.add_child(_list_section(tr("TXT_GUIDE_VERSUS_LIST_TITLE"), [
		tr("TXT_GUIDE_VERSUS_LIST_1"),
		tr("TXT_GUIDE_VERSUS_LIST_2"),
		tr("TXT_GUIDE_VERSUS_LIST_3")
	]))
	return panel


func _general_technique_section(show_title: bool = true) -> Control:
	var panel := _panel()
	var margin := _margin(panel, 20, 18, 20, 18)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	if show_title:
		box.add_child(_label(tr("TXT_GUIDE_TECH_TITLE"), 22, _c("text")))
	box.add_child(_paragraph(tr("TXT_GUIDE_TECH_BODY")))
	box.add_child(_list_section(tr("TXT_GUIDE_TECH_HIGH_VALUE_TITLE"), [
		tr("TXT_GUIDE_TECH_HIGH_VALUE_1"),
		tr("TXT_GUIDE_TECH_HIGH_VALUE_2")
	]))
	box.add_child(_list_section(tr("TXT_GUIDE_TECH_GARBAGE_TITLE"), [
		tr("TXT_GUIDE_TECH_GARBAGE_1"),
		tr("TXT_GUIDE_TECH_GARBAGE_2")
	]))
	box.add_child(_list_section(tr("TXT_GUIDE_TECH_NEXT_TITLE"), [
		tr("TXT_GUIDE_TECH_NEXT_1"),
		tr("TXT_GUIDE_TECH_NEXT_2")
	]))
	box.add_child(_list_section(tr("TXT_GUIDE_TECH_STACK_TITLE"), [
		tr("TXT_GUIDE_TECH_STACK_1"),
		tr("TXT_GUIDE_TECH_STACK_2")
	]))
	box.add_child(_list_section(tr("TXT_GUIDE_TECH_SOFT_DROP_TITLE"), [
		tr("TXT_GUIDE_TECH_SOFT_DROP_1"),
		tr("TXT_GUIDE_TECH_SOFT_DROP_2")
	]))
	return panel


func _basics_placeholder_section() -> Control:
	return _text_section(
		tr("TXT_GUIDE_REPLAY_PLACEHOLDER_TITLE"),
		tr("TXT_GUIDE_REPLAY_PLACEHOLDER_BODY")
	)


func _attack_table() -> Control:
	var panel := _panel()
	var margin := _margin(panel, 20, 18, 20, 18)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	# 标题
	box.add_child(_label(tr("TXT_GUIDE_ATK_TITLE"), 22, _c("text")))
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
		var header := _label(header_text, 14, _c("accent_text"))
		header.custom_minimum_size = Vector2(170 if header_index == 0 else 120, 32)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		header.autowrap_mode = TextServer.AUTOWRAP_OFF
		header.add_theme_stylebox_override("normal", _style(_c("accent"), _c("accent"), 4, 0))
		table_grid.add_child(header)

	# 数据行
	for row_data in ATTACK_TABLE:
		var is_high := int(row_data[2]) >= 4
		var bg := _soft("warning", 0.16) if is_high else _c("surface2")
		for cell_idx in range(3):
			var cell_label := _label(row_data[cell_idx], 14, _c("text"))
			cell_label.custom_minimum_size = Vector2(170 if cell_idx == 0 else 120, 30)
			cell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			cell_label.add_theme_stylebox_override("normal", _style(bg, _c("border"), 2, 1))
			table_grid.add_child(cell_label)

	# B2B 说明
	var b2b_panel := _panel()
	b2b_panel.add_theme_stylebox_override("panel", _style(_soft("accent", 0.08), _soft("accent", 0.4), 8, 1))
	var b2b_margin := _margin(b2b_panel, 14, 10, 14, 10)
	var b2b_box := VBoxContainer.new()
	b2b_box.add_theme_constant_override("separation", 4)
	b2b_margin.add_child(b2b_box)
	b2b_box.add_child(_label(tr("TXT_GUIDE_B2B_TITLE"), 15, _c("accent")))
	b2b_box.add_child(_paragraph(tr("TXT_GUIDE_B2B_DESC")))
	box.add_child(b2b_panel)

	# Combo 说明
	var combo_panel := _panel()
	combo_panel.add_theme_stylebox_override("panel", _style(_soft("success", 0.12), _soft("success", 0.4), 8, 1))
	var combo_margin := _margin(combo_panel, 14, 10, 14, 10)
	var combo_box := VBoxContainer.new()
	combo_box.add_theme_constant_override("separation", 4)
	combo_margin.add_child(combo_box)
	combo_box.add_child(_label(tr("TXT_GUIDE_COMBO_TITLE"), 15, _c("success")))
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
	section_box.add_child(_label(title, 19, _c("text")))
	section_box.add_child(_paragraph(text))
	return panel


func _list_section(title: String, items: Array) -> Control:
	var panel := _panel()
	var margin := _margin(panel, 18, 16, 18, 16)
	var section_box := VBoxContainer.new()
	section_box.add_theme_constant_override("separation", 8)
	margin.add_child(section_box)
	section_box.add_child(_label(title, 19, _c("text")))
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
	btn.theme_type_variation = &"AccentButton" if filled else &""


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.theme_type_variation = &"CardPanel"
	return panel


func _flatten_panel(node: Node) -> void:
	var panel := node as PanelContainer
	if panel:
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var m := panel.get_child(0) as MarginContainer
		if m:
			for side in ["margin_left", "margin_right", "margin_top"]:
				m.add_theme_constant_override(side, 0)


func _style_panel_node(node: Node) -> void:
	var panel := node as PanelContainer
	if panel:
		panel.theme_type_variation = &"CardPanel"



func _c(key: String) -> Color:
	return UITheme.color(key)


const HUES: Array[String] = ["cyan", "amber", "pink", "violet"]


func _hue(i: int) -> String:
	return HUES[posmod(i, HUES.size())]


## 色相小标签：淡色底 + 加深的同色字（保证可读性），无描边
func _hue_chip(text: String, hue: String) -> Label:
	var dark := UITheme.is_dark()
	var col := _c(hue)
	var bg := Color(col, 0.2) if dark else col.lerp(Color.WHITE, 0.72)
	var fg := col.lightened(0.15) if dark else col.darkened(0.42)
	var label := _chip(text, bg, fg)
	label.add_theme_font_override("font", get_theme_font("font", "HeaderLabel"))
	var sb := label.get_theme_stylebox("normal") as StyleBoxFlat
	sb.set_corner_radius_all(99)
	return label


func _badge_indent() -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 40
	return sb


func _hue_card(index: int, hue: String) -> ModeCard:
	var card := ModeCard.new()
	card.hue = hue
	card.index = index
	card.show_arrow = false
	card.hover_activate = true
	card.corner_radius = 20
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return card


func _soft(key: String, amount: float) -> Color:
	return UITheme.soft(key, amount)


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
	label.add_theme_color_override("font_color", _c("muted"))
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
	_stop_demo_animation()
	if content_root == null:
		return
	for child in content_root.get_children():
		content_root.remove_child(child)
		child.queue_free()
	board_view = null
