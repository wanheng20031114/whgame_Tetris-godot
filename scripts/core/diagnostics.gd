extends CanvasLayer

signal fatal_shutdown_requested
var _logger: PrototypeLogger
var _elapsed := 0.0
var _retry_elapsed := 0.0
var _last_problem := ""
var _quitting := false
@onready var _warning: PanelContainer = $Warning
@onready var _message: Label = $Warning/Margin/Rows/Message

func _ready() -> void:
	_logger = PrototypeLogger.new()
	OS.add_logger(_logger)
	$Warning/Margin/Rows/Dismiss.pressed.connect(_warning.hide)

func _process(delta: float) -> void:
	if _logger.has_fatal_error() and not _quitting:
		_quitting = true
		fatal_shutdown_requested.emit()
		_logger.flush_pending()
		get_tree().quit(70)
		return
	_elapsed += delta
	_retry_elapsed += delta
	if _elapsed < 1.0:
		return
	_elapsed = 0.0
	if _retry_elapsed >= 10.0:
		_retry_elapsed = 0.0
		PlayerDataStore.retry_pending_saves()
	_logger.flush_pending()
	var problem := StorageBudget.last_error()
	if not problem.is_empty() and problem != _last_problem:
		notify_storage_problem(problem)

func notify_storage_problem(message: String) -> void:
	_last_problem = message
	_message.text = tr("TXT_STORAGE_PAUSED") + "\n" + message.left(360)
	_warning.show()

func _exit_tree() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger.flush_pending()
