class_name DialogueTypewriter
extends Node
## Sequential native Label reveal, using arc-nice's NPC dialogue cadence.
## Full text stays shaped so wrapping and container geometry remain stable.

const LETTER_TIME := 0.035
const COMMA_TIME := 0.12
const PUNCTUATION_TIME := 0.22
const SILENT_CHARACTERS := " \t\r\n　，。？！、,.?!；：;:…—–-()（）[]【】「」『』“”‘’\"'·◆\u2060"

@export var labels: Array[Label] = []
@export var blip_audio: AudioStreamPlayer

var _line_index := 0
var _character_index := 0
var _delay_left := 0.0


func _ready() -> void:
	set_process(false)
	for label in labels:
		label.visibility_changed.connect(_on_visibility_changed)


func play() -> void:
	finish()
	for label in labels:
		if not label.is_visible_in_tree():
			return
	for label in labels:
		label.visible_characters = 0
	_line_index = 0
	_character_index = 0
	_delay_left = 0.0
	set_process(true)


func finish() -> void:
	set_process(false)
	blip_audio.stop()
	for label in labels:
		label.visible_characters = -1


func is_revealing() -> bool:
	return is_processing()


func _process(delta: float) -> void:
	_delay_left -= delta
	if _delay_left > 0.0:
		return
	while _line_index < labels.size() and _character_index >= labels[_line_index].text.length():
		_line_index += 1
		_character_index = 0
	if _line_index >= labels.size():
		finish()
		return
	var label := labels[_line_index]
	var character := label.text.substr(_character_index, 1)
	_character_index += 1
	label.visible_characters = _character_index
	if not SILENT_CHARACTERS.contains(character):
		blip_audio.play()
	# Carry fractional frame time, but never burst through characters after a stall.
	_delay_left = maxf(_delay_left + _character_delay(character), 0.0)
	if _character_index == label.text.length() and _line_index < labels.size() - 1:
		_delay_left = maxf(_delay_left, PUNCTUATION_TIME)


func _character_delay(character: String) -> float:
	if "，,、；;：:".contains(character):
		return COMMA_TIME
	if "。？！.?!…\n".contains(character):
		return PUNCTUATION_TIME
	return LETTER_TIME


func _on_visibility_changed() -> void:
	for label in labels:
		if not label.is_visible_in_tree():
			finish()
			return


func _exit_tree() -> void:
	blip_audio.stop()
