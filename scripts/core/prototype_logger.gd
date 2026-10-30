class_name PrototypeLogger
extends Logger

# Engine callbacks only enqueue bounded text; filesystem operations run on the
# main thread, outside the logger mutex, to avoid re-entering a filesystem error.
const FILE_LIMIT := 8 * 1024 * 1024
const QUEUE_LIMIT := 64 * 1024
const MESSAGE_LIMIT := 4096
const MESSAGES_PER_SECOND := 20
const UNIQUE_LIMIT := 256
var _mutex := Mutex.new()
var _queue := PackedByteArray()
var _seen: Dictionary = {}
var _second: int = -1
var _count: int = 0
var _suppressed: int = 0
var _fatal: bool = false
var _stopped: bool = false
var _path: String = ""

func _init() -> void:
	_path = StorageBudget.data_root().path_join("diagnostics").path_join("%s-%s-%s.log" % [int(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec()])

func _log_message(message: String, error: bool) -> void:
	_enqueue(message, error)

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	_enqueue("%s:%d %s: %s %s" % [file.left(256), line, function.left(256), code.left(1024), rationale.left(1024)], true)

func _enqueue(message: String, error: bool) -> void:
	# Limit before UTF-8 conversion (one Unicode character can use four bytes).
	var bounded := message.left(MESSAGE_LIMIT / 4)
	var lower := bounded.to_lower()
	_mutex.lock()
	if "0x887a0005" in lower or "0x887a0006" in lower or "0x887a0007" in lower or "device_removed" in lower or "device_hung" in lower or "device lost" in lower or "invalid vertex array" in lower or "buffer_create" in lower:
		_fatal = true
	if not _stopped:
		var second := Time.get_ticks_msec() / 1000
		if second != _second:
			_second = second
			_count = 0
		var key := bounded.hash()
		if _count >= MESSAGES_PER_SECOND or _seen.has(key) or _seen.size() >= UNIQUE_LIMIT:
			_suppressed = mini(_suppressed + 1, 2147483647)
		else:
			var bytes := ("[%d] %s %s\n" % [Time.get_ticks_msec(), "ERROR" if error else "INFO", bounded]).to_utf8_buffer()
			if _queue.size() + bytes.size() <= QUEUE_LIMIT:
				_queue.append_array(bytes)
				_seen[key] = true
				_count += 1
			else:
				_suppressed = mini(_suppressed + 1, 2147483647)
	_mutex.unlock()

func has_fatal_error() -> bool:
	_mutex.lock()
	var result := _fatal
	_mutex.unlock()
	return result

func flush_pending() -> Error:
	_mutex.lock()
	var bytes := _queue
	_queue = PackedByteArray()
	_seen.clear()
	if _suppressed > 0 and not _stopped:
		bytes.append_array(("[logger] Suppressed %d repeated or excess messages.\n" % _suppressed).to_utf8_buffer())
	_suppressed = 0
	var stopped := _stopped
	_mutex.unlock()
	if stopped or bytes.is_empty():
		return OK
	var result := StorageBudget.append_bounded(_path, bytes, FILE_LIMIT)
	if result != OK:
		_mutex.lock()
		_stopped = true
		_queue.clear()
		_mutex.unlock()
	return result
