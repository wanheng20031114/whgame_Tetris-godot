class_name AyaoAssistantPanel
extends PanelContainer
## Presentation only: the coach's facts and future API provider stay outside UI.

signal plan_requested

@onready var body_label: Label = %Observation
@onready var advice_label: Label = %Advice
@onready var title_label: Label = %ReviewTitle
@onready var step_label: Label = %ReviewStep
@onready var plan_button: Button = %PlanButton
@onready var toggle_button: Button = %ToggleButton
@onready var details: VBoxContainer = %Details
@onready var portrait: TextureRect = %Portrait
@onready var idle_animation: AnimationPlayer = $AnimationPlayer
@onready var advice_card: PanelContainer = %AdviceCard
@onready var typewriter: DialogueTypewriter = $Typewriter

var _current_step := -1
var _total_steps := 0
var _review: Dictionary = {}
var _collapsed := false
var _has_plan := false
var _plan_preview := false
var _reaction: Tween


func _ready() -> void:
	toggle_button.pressed.connect(_toggle_collapsed)
	plan_button.pressed.connect(func(): plan_requested.emit())
	UITheme.theme_changed.connect(_on_theme_changed)
	portrait.pivot_offset = portrait.size * 0.5
	_refresh_text()
	_apply_palette()


func present_review(step: int, total: int, review: Dictionary, has_plan: bool) -> void:
	var changed := step != _current_step or review != _review
	_current_step = step
	_total_steps = total
	_review = review.duplicate(true)
	_has_plan = has_plan
	_refresh_text(changed)
	_apply_palette()
	if changed and not _collapsed:
		_react()


func clear_review() -> void:
	typewriter.finish()
	_current_step = -1
	_total_steps = 0
	_review.clear()
	_has_plan = false
	_plan_preview = false
	if _reaction:
		_reaction.kill()
	portrait.scale = Vector2.ONE
	body_label.modulate = Color.WHITE
	_refresh_text()
	_apply_palette()


func set_plan_preview(active: bool) -> void:
	_plan_preview = active
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text(animate_review: bool = false) -> void:
	%AssistantName.text = tr("TXT_AYAO_NAME")
	%SourceLabel.text = tr("TXT_AYAO_LOCAL")
	%AdviceHeading.text = tr("TXT_AYAO_ADVICE_HEADING")
	toggle_button.text = "+" if _collapsed else "−"
	toggle_button.tooltip_text = tr("TXT_AYAO_EXPAND" if _collapsed else "TXT_AYAO_COLLAPSE")
	plan_button.text = tr("TXT_AYAO_HIDE_PLAN" if _plan_preview else "TXT_AYAO_VIEW_PLAN")
	plan_button.visible = _has_plan
	var body_text: String
	var advice_text: String
	if _current_step < 0:
		step_label.text = tr("TXT_AYAO_WAITING")
		title_label.text = tr("TXT_AYAO_WELCOME_TITLE")
		body_text = tr("TXT_AYAO_WELCOME_BODY")
		advice_text = tr("TXT_AYAO_WELCOME_ADVICE")
	else:
		step_label.text = (tr("TXT_AYAO_STEP") % [_current_step + 1, _total_steps]) + "\n" + tr("TXT_AYAO_AFTER_CLEAR")
		title_label.text = tr(_review["title_key"])
		body_text = _format_message(_review["body_key"], _review["body_args"])
		advice_text = _format_message(_review["advice_key"], _review["advice_args"])
	if body_text != body_label.text or advice_text != advice_label.text:
		typewriter.finish()
		body_label.text = body_text
		advice_label.text = advice_text
	if animate_review and not _collapsed and is_visible_in_tree():
		typewriter.play()


func _format_message(key: String, args: Array) -> String:
	return tr(key) if args.is_empty() else tr(key) % args


func _toggle_collapsed() -> void:
	_collapsed = not _collapsed
	details.visible = not _collapsed
	if _collapsed:
		typewriter.finish()
		idle_animation.pause()
		if _reaction:
			_reaction.kill()
		portrait.scale = Vector2.ONE
		body_label.modulate = Color.WHITE
	else:
		idle_animation.play("idle")
	_refresh_text()


func _react() -> void:
	if _reaction:
		_reaction.kill()
	portrait.scale = Vector2.ONE
	_reaction = create_tween()
	_reaction.tween_property(portrait, "scale", Vector2.ONE * 1.06, 0.12).set_trans(Tween.TRANS_SINE)
	_reaction.chain().tween_property(portrait, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SINE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if typewriter.is_revealing():
			typewriter.finish()
			accept_event()


func _on_theme_changed(_mode: String) -> void:
	_apply_palette()


func _apply_palette() -> void:
	var hue := "accent"
	if _review.get("kind") == "praise":
		hue = "success"
	elif _review.get("kind") == "tip":
		hue = "amber"
	var card: StyleBoxFlat = get_theme_stylebox("panel")
	card.bg_color = UITheme.color("surface2")
	card.border_color = UITheme.color(hue).lerp(UITheme.color("surface2"), 0.55)
	var hint: StyleBoxFlat = advice_card.get_theme_stylebox("panel")
	hint.bg_color = UITheme.color("surface2").lerp(UITheme.color(hue), 0.12)
	var title_color := UITheme.color(hue) if UITheme.is_dark() else UITheme.color("text").lerp(UITheme.color(hue), 0.5)
	title_label.add_theme_color_override("font_color", title_color)
	body_label.add_theme_color_override("font_color", UITheme.color("text"))
	advice_label.add_theme_color_override("font_color", UITheme.color("text"))
