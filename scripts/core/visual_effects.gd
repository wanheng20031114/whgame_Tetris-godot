class_name VisualEffects
extends RefCounted

enum Level { FULL, LIGHT, OFF }

const SECTION := "VisualEffects"
const DROP_TRAIL := "drop_trail"
const LINE_CLEAR := "line_clear"
const ATTACK_TRAIL := "attack_trail"

static var _levels: Dictionary[String, Level] = {
	DROP_TRAIL: Level.FULL,
	LINE_CLEAR: Level.FULL,
	ATTACK_TRAIL: Level.FULL,
}


static func load_settings(config: ConfigFile) -> void:
	for effect in _levels:
		match config.get_value(SECTION, effect, Level.FULL):
			Level.LIGHT: _levels[effect] = Level.LIGHT
			Level.OFF: _levels[effect] = Level.OFF
			_: _levels[effect] = Level.FULL


static func get_level(effect: String) -> Level:
	return _levels[effect]


static func set_level(effect: String, level: Level) -> void:
	_levels[effect] = level
