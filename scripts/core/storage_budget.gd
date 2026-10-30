class_name StorageBudget
extends RefCounted

# All cooperating writers share directory/session budgets and one filesystem lock.
# Existing files are retained. A full budget rejects new writes.
const SESSION_BYTES: int = 1_000_000_000
const TOTAL_BYTES: int = 20_000_000_000
const LOCK_OWNER_LIMIT: int = 256
const RESERVATION_LIMIT: int = 2048
static var _mutex := Mutex.new()
static var _root_override: String = ""
static var _started: bool = false
static var _error_message: String = ""
static var _total_limit: int = TOTAL_BYTES
static var _session_limit: int = SESSION_BYTES

static func data_root() -> String:
	_mutex.lock()
	var result := _root()
	_mutex.unlock()
	return result

static func configure_root_for_tests(path: String, total_limit: int = TOTAL_BYTES, session_limit: int = SESSION_BYTES) -> Error:
	_mutex.lock()
	var result: Error = OK
	var isolated_test := _is_isolated_test_path(path)
	if (_started and not isolated_test) or not path.is_absolute_path() or total_limit <= LOCK_OWNER_LIMIT or total_limit > TOTAL_BYTES or session_limit <= 0 or session_limit > SESSION_BYTES:
		result = _fail(ERR_INVALID_PARAMETER, "Test storage root must be absolute and configured before storage is used.")
	else:
		_root_override = path.simplify_path().trim_suffix("/").trim_suffix("\\")
		_total_limit = total_limit
		_session_limit = session_limit
	_mutex.unlock()
	return result

static func last_error() -> String:
	_mutex.lock()
	var result := _error_message
	_mutex.unlock()
	return result

static func clear_error() -> void:
	_mutex.lock()
	_error_message = ""
	_mutex.unlock()

static func report_error(message: String) -> void:
	_mutex.lock()
	_error_message = message
	_mutex.unlock()

static func read_bounded(path: String, max_bytes: int) -> Dictionary:
	_mutex.lock()
	# Read-only access must remain available even when the write budget is full.
	var result := _read(path, max_bytes)
	_mutex.unlock()
	return result

static func write_atomic(path: String, bytes: PackedByteArray, per_file_limit: int, keep_backup: bool = true) -> Error:
	_mutex.lock()
	var err := _acquire()
	if err == OK:
		err = _write_atomic(path, bytes, per_file_limit, keep_backup)
		_release()
	_mutex.unlock()
	return err

static func append_bounded(path: String, bytes: PackedByteArray, per_file_limit: int) -> Error:
	_mutex.lock()
	var err := _acquire()
	if err == OK:
		if not _inside(path) or per_file_limit <= 0:
			err = _fail(ERR_INVALID_PARAMETER, "Invalid diagnostic output path or limit.")
		else:
			var existing := _size(path)
			if existing + bytes.size() > per_file_limit:
				err = _fail(ERR_OUT_OF_MEMORY, "Diagnostic file limit reached; further records were stopped: " + path)
			else:
				err = _check_capacity(path, bytes.size())
				if err == OK:
					err = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
				if err == OK:
					var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
					if file == null:
						err = _fail(FileAccess.get_open_error(), "Cannot open diagnostic output: " + path)
					else:
						file.seek_end()
						file.store_buffer(bytes)
						file.flush()
						err = file.get_error()
						file.close()
						if err != OK:
							_fail(err, "Diagnostic write failed; disk space or permissions may be unavailable: " + path)
		_release()
	_mutex.unlock()
	return err

static func update_json_atomic(path: String, per_file_limit: int, updater: Callable) -> Error:
	_mutex.lock()
	var err := _acquire()
	if err == OK:
		var value: Dictionary = {}
		if not FileAccess.file_exists(path):
			var parent := DirAccess.open(path.get_base_dir())
			if parent != null:
				parent.include_hidden = true
				for name in parent.get_files():
					if name.begins_with(path.get_file() + ".bak."):
						err = _fail(ERR_FILE_CORRUPT, "A previous save exists but its primary file is missing; recovery is required: " + path)
		if FileAccess.file_exists(path):
			var loaded := _read(path, per_file_limit)
			err = loaded.error
			if err == OK:
				var parsed = _json_value((loaded.data as PackedByteArray).get_string_from_utf8())
				if not (parsed is Dictionary):
					err = _fail(ERR_PARSE_ERROR, "Statistics are damaged; the existing file was retained: " + path)
				else:
					value = parsed
		if err == OK:
			var updated = updater.call(value)
			if not (updated is Dictionary):
				err = _fail(ERR_INVALID_DATA, "Statistics contain malformed fields; the existing file and backups were retained.")
			else:
				err = _write_atomic(path, JSON.stringify(updated, "\t").to_utf8_buffer(), per_file_limit, true)
		_release()
	_mutex.unlock()
	return err

# Reserved capacity includes the output's future bytes, so another process
# cannot consume the space between starting and committing an analysis.
static func reserve_output(path: String, max_bytes: int) -> Dictionary:
	_mutex.lock()
	var err := _acquire()
	var token := ""
	if err == OK:
		if not _inside(path) or max_bytes <= 0 or FileAccess.file_exists(path):
			err = _fail(ERR_INVALID_PARAMETER, "Analysis requires a new output path inside the storage root.")
		else:
			token = _unique()
			var marker := _root().path_join(".reservations").path_join(token + ".json")
			var bytes := JSON.stringify({"protocol": 1, "path": _absolute(path), "max_bytes": max_bytes, "parent_pid": OS.get_process_id()}).to_utf8_buffer()
			err = _check_capacity(path, max_bytes + bytes.size(), true) if max_bytes <= _total_limit else _fail(ERR_OUT_OF_MEMORY, "Analysis reservation exceeds the userdata directory budget.")
			if err == OK:
				err = _store_new(marker, bytes)
		_release()
	_mutex.unlock()
	return {"error": err, "token": token if err == OK else ""}

static func release_reservation(token: String) -> Error:
	_mutex.lock()
	var err := _acquire()
	if err == OK:
		if not token.is_valid_hex_number(false) or token.length() != 32:
			err = _fail(ERR_INVALID_PARAMETER, "Invalid analysis reservation token.")
		else:
			var marker := _root().path_join(".reservations").path_join(token + ".json")
			if FileAccess.file_exists(marker):
				err = DirAccess.remove_absolute(marker)
		_release()
	_mutex.unlock()
	return err

static func discard_reserved(token: String) -> Error:
	_mutex.lock()
	var err := _acquire()
	if err == OK:
		if not token.is_valid_hex_number(false) or token.length() != 32:
			err = _fail(ERR_INVALID_PARAMETER, "Invalid analysis reservation token.")
		else:
			var marker := _root().path_join(".reservations").path_join(token + ".json")
			var loaded := _read(marker, RESERVATION_LIMIT)
			err = loaded.error
			if err == OK:
				var info = _json_value((loaded.data as PackedByteArray).get_string_from_utf8())
				if not (info is Dictionary) or int(info.get("parent_pid", 0)) != OS.get_process_id() or not _inside(str(info.get("path", ""))):
					err = _fail(ERR_INVALID_DATA, "Refusing to remove output not reserved by this process.")
				else:
					if FileAccess.file_exists(str(info.path)):
						err = DirAccess.remove_absolute(str(info.path))
					if err == OK:
						err = DirAccess.remove_absolute(marker)
		_release()
	_mutex.unlock()
	return err

# Renaming a completed reserved file consumes no additional file bytes.
static func commit_reserved(token: String, destination: String) -> Error:
	_mutex.lock()
	var err := _acquire()
	if err == OK:
		var marker := _root().path_join(".reservations").path_join(token + ".json")
		var loaded := _read(marker, RESERVATION_LIMIT)
		err = loaded.error
		if err == OK:
			var info = _json_value((loaded.data as PackedByteArray).get_string_from_utf8())
			if not (info is Dictionary) or not _inside(destination) or not _inside(str(info.get("path", ""))):
				err = _fail(ERR_INVALID_DATA, "Invalid reserved analysis output.")
			else:
				var source := str(info.path)
				# Capacity belongs to the source session. Renames may not transfer
				# it to a different session or convert ungrouped data into a session.
				if _session_key(source) != _session_key(destination):
					err = _fail(ERR_INVALID_PARAMETER, "Reserved analysis output must retain its session identity.")
				elif not FileAccess.file_exists(source) or _size(source) > int(info.max_bytes):
					err = _fail(ERR_FILE_CORRUPT, "Analysis output is missing or exceeds its reserved limit.")
				else:
					err = _replace_with_backup(source, destination, true)
					if err == OK:
						DirAccess.remove_absolute(marker)
		_release()
	_mutex.unlock()
	return err

static func _root() -> String:
	if not _root_override.is_empty():
		return _root_override
	return ProjectSettings.globalize_path("res://userdata") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("userdata")

static func _is_isolated_test_path(path: String) -> bool:
	if OS.get_environment("TETRIS_SAFE_RUN") != "1" or not OS.has_feature("editor"):
		return false
	var run_dir := OS.get_environment("TETRIS_RUN_DIR").replace("\\", "/").simplify_path().trim_suffix("/")
	var marker := FileAccess.open("res://.safe-run-isolated.json", FileAccess.READ)
	if marker == null or marker.get_length() > 4096 or not run_dir.is_absolute_path():
		return false
	var info = _json_value(marker.get_as_text())
	marker.close()
	if not (info is Dictionary) or info.get("kind") != "tetris-isolated-test":
		return false
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/")
	return run_dir.to_lower().begins_with(project_root.to_lower() + "/") and path.replace("\\", "/").simplify_path().to_lower().begins_with(run_dir.to_lower() + "/")

static func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()

static func _inside(path: String) -> bool:
	var root := _absolute(_root()).trim_suffix("/") + "/"
	var candidate := _absolute(path)
	if OS.get_name() == "Windows":
		root = root.to_lower()
		candidate = candidate.to_lower()
	return candidate.begins_with(root) and not candidate.contains("/.budget-write-lock/") and not _path_has_link(_absolute(path))

static func _path_has_link(path: String) -> bool:
	var current := _absolute(path).trim_suffix("/")
	while not current.is_empty():
		var parent_path := current.get_base_dir()
		if parent_path == current or parent_path.is_empty():
			break
		var parent := DirAccess.open(parent_path)
		if parent != null and parent.is_link(current.get_file()):
			return true
		current = parent_path
	return false

static func _fail(code: Error, message: String) -> Error:
	_error_message = message
	return code

static func _json_value(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null

static func _unique() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size

static func _read(path: String, limit: int) -> Dictionary:
	if not _inside(path) or limit <= 0:
		return {"error": _fail(ERR_INVALID_PARAMETER, "Read path is outside the game data directory."), "data": PackedByteArray()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": _fail(FileAccess.get_open_error(), "Cannot read stored data: " + path), "data": PackedByteArray()}
	var actual_size := file.get_length()
	if actual_size > limit:
		file.close()
		return {"error": _fail(ERR_OUT_OF_MEMORY, "Stored file exceeds its read limit: " + path), "data": PackedByteArray()}
	var bytes := file.get_buffer(actual_size)
	var size_after_read := file.get_length()
	file.close()
	if bytes.size() != actual_size or size_after_read != actual_size:
		return {"error": _fail(ERR_BUSY, "Stored file changed while being read; retry without replacing it: " + path), "data": PackedByteArray()}
	return {"error": OK, "data": bytes}

static func _acquire() -> Error:
	_started = true
	if _path_has_link(_root()):
		return _fail(ERR_INVALID_PARAMETER, "Refusing a storage root or ancestor that is a link or junction.")
	var err := DirAccess.make_dir_recursive_absolute(_root())
	if err != OK:
		return _fail(err, "Cannot create the game data directory: " + _root())
	var lock_dir := _root().path_join(".budget-write-lock")
	err = DirAccess.make_dir_absolute(lock_dir)
	if err != OK:
		# Never reclaim from a PID observation: two reclaimers could remove a
		# new owner's lock. An interrupted write lock requires explicit recovery.
		return _fail(ERR_BUSY, "Storage is busy in another game process, or an interrupted write lock requires explicit recovery. Pending saves were retained.")
	var owner_bytes := JSON.stringify({"pid": OS.get_process_id()}).to_utf8_buffer()
	if _usage() + owner_bytes.size() > _total_limit:
		DirAccess.remove_absolute(lock_dir)
		return _fail(ERR_OUT_OF_MEMORY, "The 20,000,000,000-byte userdata directory budget is full; existing data was retained.")
	err = _store_new(lock_dir.path_join("owner.json"), owner_bytes)
	if err != OK:
		_release()
	return err

static func _release() -> void:
	var lock_dir := _root().path_join(".budget-write-lock")
	DirAccess.remove_absolute(lock_dir.path_join("owner.json"))
	DirAccess.remove_absolute(lock_dir)

static func _usage() -> int:
	return int(_usage_breakdown().total)

# A session's primary, analyzed output, and suffix-based temporary/backup
# files keep the same identity even if moved into a hidden or archive folder.
# Other filenames consume only the shared directory budget.
static func _session_key(path: String) -> String:
	var name := path.get_file()
	if OS.get_name() == "Windows":
		name = name.to_lower()
	if not name.begins_with("session_"):
		return ""
	var json_at := name.find(".json", 8)
	if json_at <= 8 or (json_at + 5 < name.length() and name.substr(json_at + 5, 1) != "."):
		return ""
	var stem := name.left(json_at).trim_suffix("_analyzed")
	return stem if stem.length() > 8 else ""

static func _path_key(path: String) -> String:
	var absolute := _absolute(path)
	return absolute.to_lower() if OS.get_name() == "Windows" else absolute

static func _invalid_usage() -> Dictionary:
	return {"valid": false, "total": TOTAL_BYTES + 1, "sessions": {}}

static func _add_usage(usage: Dictionary, size: int, session: String) -> void:
	# Saturation both fails closed and prevents integer overflow from huge
	# pre-existing files. Existing over-limit sessions do not block other ones.
	var bounded := mini(size, TOTAL_BYTES + 1)
	usage.total = mini(int(usage.total) + bounded, TOTAL_BYTES + 1)
	if not session.is_empty():
		usage.sessions[session] = mini(int(usage.sessions.get(session, 0)) + bounded, SESSION_BYTES + 1)

static func _check_capacity(path: String, additional_bytes: int, new_reservation: bool = false) -> Error:
	var usage := _usage_breakdown()
	if not usage.valid:
		return _fail(ERR_INVALID_DATA, "Cannot verify userdata storage usage; existing data was retained.")
	if new_reservation and usage.reserved.has(_path_key(path)):
		return _fail(ERR_ALREADY_EXISTS, "Analysis output already has an active reservation: " + path)
	if additional_bytes < 0 or additional_bytes > _total_limit or int(usage.total) > _total_limit - additional_bytes:
		return _fail(ERR_OUT_OF_MEMORY, "The 20,000,000,000-byte userdata directory budget is full; existing data was retained.")
	var session := _session_key(path)
	if not session.is_empty() and (additional_bytes > _session_limit or int(usage.sessions.get(session, 0)) > _session_limit - additional_bytes):
		return _fail(ERR_OUT_OF_MEMORY, "The 1,000,000,000-byte session budget is full for " + session + "; existing data was retained.")
	return OK

static func _usage_breakdown() -> Dictionary:
	var reserved: Dictionary = {}
	var marker_sessions: Dictionary = {}
	var usage := {"valid": true, "total": 0, "sessions": {}, "reserved": reserved}
	var reservations_path := _root().path_join(".reservations")
	if _path_has_link(reservations_path):
		return _invalid_usage()
	var reservations := DirAccess.open(reservations_path)
	if reservations != null:
		reservations.include_hidden = true
		for name in reservations.get_files():
			if reservations.is_link(name):
				return _invalid_usage()
			var path := reservations_path.path_join(name)
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null or file.get_length() > RESERVATION_LIMIT:
				return _invalid_usage()
			var info = _json_value(file.get_as_text())
			file.close()
			if not (info is Dictionary) or not _inside(str(info.get("path", ""))):
				return _invalid_usage()
			var limit := int(info.get("max_bytes", TOTAL_BYTES + 1))
			if limit <= 0 or limit > _total_limit:
				return _invalid_usage()
			var key := _path_key(str(info.path))
			if reserved.has(key):
				return _invalid_usage()
			var session := _session_key(str(info.path))
			reserved[key] = limit
			marker_sessions[_path_key(path)] = session
			_add_usage(usage, limit, session)
	# Do not sample a growing reserved file twice: counting full capacity and
	# excluding its physical bytes avoids a cross-process time-of-check race.
	if not _scan_directory(_root(), reserved, marker_sessions, usage):
		return _invalid_usage()
	return usage

static func _scan_directory(path: String, reserved: Dictionary, marker_sessions: Dictionary, usage: Dictionary) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.include_hidden = true
	for name in dir.get_files():
		if dir.is_link(name):
			return false
		var full_path := _absolute(path.path_join(name))
		var key := _path_key(full_path)
		var file := FileAccess.open(path.path_join(name), FileAccess.READ)
		if file == null:
			return false
		var size := file.get_length()
		file.close()
		if reserved.has(key):
			if size > int(reserved[key]):
				return false
			continue
		_add_usage(usage, size, str(marker_sessions.get(key, _session_key(full_path))))
	for name in dir.get_directories():
		if dir.is_link(name):
			return false
		if not _scan_directory(path.path_join(name), reserved, marker_sessions, usage):
			return false
	return true

static func _store_new(path: String, bytes: PackedByteArray) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		return _fail(err, "Cannot create output directory: " + path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail(FileAccess.get_open_error(), "Cannot create output: " + path)
	file.store_buffer(bytes)
	file.flush()
	err = file.get_error()
	file.close()
	if err != OK or _size(path) != bytes.size():
		DirAccess.remove_absolute(path)
		return _fail(ERR_FILE_CANT_WRITE, "Write failed; existing data was retained: " + path)
	return OK

static func _write_atomic(path: String, bytes: PackedByteArray, limit: int, backup: bool) -> Error:
	if not _inside(path) or limit <= 0 or bytes.size() > limit:
		return _fail(ERR_OUT_OF_MEMORY, "Save exceeds its file limit, or uses an invalid output path: " + path)
	var capacity_error := _check_capacity(path, bytes.size())
	if capacity_error != OK:
		return capacity_error
	var temporary := path + ".tmp." + _unique()
	var err := _store_new(temporary, bytes)
	if err != OK:
		return err
	err = _replace_with_backup(temporary, path, backup)
	if err != OK:
		DirAccess.remove_absolute(temporary)
	return err

static func _replace_with_backup(source: String, destination: String, backup: bool) -> Error:
	var previous := ""
	if FileAccess.file_exists(destination):
		if not backup:
			return _fail(ERR_ALREADY_EXISTS, "Refusing to replace existing data: " + destination)
		previous = destination + ".bak." + str(Time.get_unix_time_from_system()) + "." + _unique()
		var move_old := DirAccess.rename_absolute(destination, previous)
		if move_old != OK:
			return _fail(move_old, "Cannot preserve the previous save: " + destination)
	var err := DirAccess.rename_absolute(source, destination)
	if err != OK:
		if not previous.is_empty():
			DirAccess.rename_absolute(previous, destination)
		return _fail(err, "Cannot commit the new save; its previous version was retained: " + destination)
	return OK
