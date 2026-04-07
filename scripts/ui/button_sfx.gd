extends Node

const AUDIO_CANDIDATES := [
	"res://audio/click.ogg",
	"res://audio/click.wav",
	"res://audio/click.m4a"
]

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "ButtonClickPlayer"
	_player.bus = "Master"
	_player.stream = _load_click_stream()
	add_child(_player)

	var tree := get_tree()
	tree.node_added.connect(_on_node_added)
	_register_existing_buttons(tree.root)


func _register_existing_buttons(root: Node) -> void:
	if root is BaseButton:
		_register_button(root as BaseButton)
	if root is OptionButton:
		_register_option_button(root as OptionButton)

	for child in root.get_children():
		_register_existing_buttons(child)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_register_button(node as BaseButton)
	if node is OptionButton:
		_register_option_button(node as OptionButton)


func _register_button(button: BaseButton) -> void:
	var callback := Callable(self, "_on_button_pressed")
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _register_option_button(option_button: OptionButton) -> void:
	var callback := Callable(self, "_on_option_selected")
	if not option_button.item_selected.is_connected(callback):
		option_button.item_selected.connect(callback)


func play_click() -> void:
	if _player == null or _player.stream == null:
		return
	if _player.playing:
		_player.stop()
	_player.play()


func _on_button_pressed() -> void:
	play_click()


func _on_option_selected(_index: int) -> void:
	play_click()


func _load_click_stream() -> AudioStream:
	for path in AUDIO_CANDIDATES:
		if ResourceLoader.exists(path):
			var stream := load(path)
			if stream is AudioStream:
				return stream as AudioStream
	push_warning("[ButtonSfx] Click sound not found. Checked: %s" % ", ".join(PackedStringArray(AUDIO_CANDIDATES)))
	return null
