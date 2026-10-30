class_name ReplayAiEnvironment
extends RefCounted

const WINDOWS_ANALYZER_RESOURCE := "res://replay-ai-core/bin/windows/analyze_session.exe"
const PROTOCOL := "TETRIS_STORAGE_V1"
const MAX_ANALYZER_BYTES: int = 64_000_000
static var _verified_path := ""

static func ensure_analyzer_available() -> String:
	if not _verified_path.is_empty():
		return _verified_path
	if OS.get_name() != "Windows":
		StorageBudget.report_error("This prototype requires the bundled Windows replay analyzer.")
		return ""
	var source := FileAccess.open(WINDOWS_ANALYZER_RESOURCE, FileAccess.READ)
	if source == null or source.get_length() > MAX_ANALYZER_BYTES:
		StorageBudget.report_error("The bounded replay analyzer is missing or exceeds its size limit.")
		return ""
	var bytes := source.get_buffer(MAX_ANALYZER_BYTES + 1)
	source.close()
	if bytes.size() > MAX_ANALYZER_BYTES:
		StorageBudget.report_error("The replay analyzer grew beyond its size limit.")
		return ""
	var target := StorageBudget.data_root().path_join("bin/analyze_session-v1.exe")
	var matches := false
	if FileAccess.file_exists(target):
		var cached := StorageBudget.read_bounded(target, MAX_ANALYZER_BYTES)
		matches = cached.error == OK and cached.data == bytes
	if not matches:
		if StorageBudget.write_atomic(target, bytes, MAX_ANALYZER_BYTES, true) != OK:
			return ""
	# An old executable receives one option only, so its usage path exits.
	if not _probe_protocol(target):
		StorageBudget.report_error("Replay analysis is unavailable: rebuild the bundled analyzer with storage protocol V1. An older unbounded binary will not be used.")
		return ""
	_verified_path = target
	return target

static func find_analyzer() -> String:
	return ensure_analyzer_available()

static func _probe_protocol(path: String) -> bool:
	var process := OS.execute_with_pipe(path, ["--storage-protocol"], false)
	if process.is_empty():
		return false
	var pid := int(process.pid)
	var pipe: FileAccess = process.stdio
	var received := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline and received.size() < 128:
		received.append_array(pipe.get_buffer(128 - received.size()))
		if not OS.is_process_running(pid):
			received.append_array(pipe.get_buffer(128 - received.size()))
			break
		OS.delay_msec(5)
	var timed_out := OS.is_process_running(pid)
	if timed_out:
		OS.kill(pid)
	pipe.close()
	var stderr_pipe: FileAccess = process.stderr
	stderr_pipe.close()
	return not timed_out and received.get_string_from_utf8().strip_edges() == PROTOCOL
