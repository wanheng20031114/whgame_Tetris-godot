extends TextureButton

var canvas_layer: CanvasLayer
var panel: PanelContainer
var option_btn: OptionButton
var close_btn: Button
var title_lbl: Label
var lang_lbl: Label

func _ready() -> void:
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		var loc = config.get_value("Settings", "locale", "en")
		TranslationServer.set_locale(loc)
	
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	
	panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.5, 0.5, 0.8, 1)
	panel.add_theme_stylebox_override("panel", sb)
	
	panel.custom_minimum_size = Vector2(400, 300)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.add_child(vbox)
	panel.add_child(margin)
	
	title_lbl = Label.new()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title_lbl)
	
	var lang_hbox = HBoxContainer.new()
	lang_lbl = Label.new()
	lang_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_hbox.add_child(lang_lbl)
	
	option_btn = OptionButton.new()
	option_btn.add_item("English", 0)
	option_btn.add_item("中文", 1)
	option_btn.add_item("日本語", 2)
	
	var current_loc = TranslationServer.get_locale()
	if current_loc.begins_with("zh"): option_btn.selected = 1
	elif current_loc.begins_with("ja"): option_btn.selected = 2
	else: option_btn.selected = 0
	
	option_btn.item_selected.connect(_on_language_selected)
	lang_hbox.add_child(option_btn)
	vbox.add_child(lang_hbox)
	
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	close_btn = Button.new()
	close_btn.text = "OK"
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.pressed.connect(func(): hide_menu())
	vbox.add_child(close_btn)
	
	canvas_layer.add_child(panel)
	add_child(canvas_layer)
	
	# 初始化不可见
	canvas_layer.hide()
	
	# 绑定自身的点击事件
	self.pressed.connect(_on_gear_pressed)
	
	_update_texts()

func _on_gear_pressed() -> void:
	if canvas_layer.visible: hide_menu()
	else: show_menu()

func show_menu() -> void:
	canvas_layer.show()

func hide_menu() -> void:
	canvas_layer.hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_update_texts()

func _update_texts() -> void:
	if title_lbl: title_lbl.text = tr("TXT_SETTINGS")
	if lang_lbl: lang_lbl.text = tr("TXT_LANGUAGE")

func _on_language_selected(idx: int) -> void:
	var loc = "en"
	match idx:
		0: loc = "en"
		1: loc = "zh"
		2: loc = "ja"
	TranslationServer.set_locale(loc)
	
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("Settings", "locale", loc)
	config.save("user://settings.cfg")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and canvas_layer and canvas_layer.visible:
		hide_menu()
		get_viewport().set_input_as_handled()
