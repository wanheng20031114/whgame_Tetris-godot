extends CheckButton


func _ready() -> void:
	SettingsMenu.bind_landing_preview_toggle(self)
