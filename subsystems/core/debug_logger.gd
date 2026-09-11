class_name DebugLogger
extends RefCounted
## Core multi-subsystem debug logging engine.
## Manages file I/O to user://logs/debug.log (or configured path) and terminal output
## based on GameConfig settings and per-subsystem toggles.

const _CONFIG_PATH := "res://data/game_config.tres"

static var _initialized: bool = false
static var _log_to_file: bool = true
static var _log_to_console: bool = false
static var _log_file_path: String = "user://logs/debug.log"
static var _subsystem_flags: Dictionary = {}
static var _file_handle: FileAccess = null
static var _printed_startup_path: bool = false
const _FLUSH_THRESHOLD_LINES: int = 40
const _FLUSH_INTERVAL_MS: int = 1000
static var _unflushed_lines: int = 0
static var _last_flush_ms: int = 0


# =================
# Primary Functions
# =================

## Writes a formatted log entry for a specific subsystem if that subsystem is enabled.
static func log_msg(subsystem: StringName, message: String) -> void:
	# 1. State Initialization: Ensure configuration and file handle are ready.
	_ensure_initialized()

	# 2. Subsystem Gate: Skip if logging is disabled for this specific subsystem.
	if not is_subsystem_enabled(subsystem):
		return

	# 3. Message Formatting: Construct timestamped entry with subsystem tag.
	var entry_line: String = _format_entry(subsystem, message)

	# 4. File Output: Write entry to the log file if file logging is enabled.
	_write_to_file(entry_line)

	# 5. Console Output: Print entry to standard output if console logging is enabled.
	_write_to_console(entry_line)


## Alias for log_msg.
static func log(subsystem: StringName, message: String) -> void:
	# 1. Message Dispatch: Delegate directly to log_msg.
	log_msg(subsystem, message)


## Returns whether debug logging is enabled for the specified subsystem.
static func is_subsystem_enabled(subsystem: StringName) -> bool:
	# 1. State Initialization: Ensure configuration is loaded before checking flags.
	_ensure_initialized()

	return bool(_subsystem_flags.get(subsystem, false))


## Overrides the debug logging flag for a specific subsystem at runtime.
static func set_subsystem_enabled(subsystem: StringName, enabled: bool) -> void:
	# 1. State Initialization: Ensure configuration is loaded before modifying flags.
	_ensure_initialized()

	_subsystem_flags[subsystem] = enabled


## Configures whether logs should be written to file.
static func set_log_to_file(enabled: bool) -> void:
	# 1. State Initialization: Ensure configuration is loaded before modifying settings.
	_ensure_initialized()

	_log_to_file = enabled
	if not enabled:
		# 1. File Cleanup: Close file handle when file logging is turned off.
		_close_file()


## Configures whether logs should be printed to the stdout console.
static func set_log_to_console(enabled: bool) -> void:
	# 1. State Initialization: Ensure configuration is loaded before modifying settings.
	_ensure_initialized()

	_log_to_console = enabled


## Changes the target log file path at runtime.
static func set_log_file_path(path: String) -> void:
	# 1. State Initialization: Ensure configuration is loaded before modifying path.
	_ensure_initialized()

	# 2. File Cleanup: Close existing file handle before switching path.
	_close_file()

	_log_file_path = path


## Returns the configured virtual log file path (e.g. user://logs/debug.log).
static func get_log_file_path() -> String:
	# 1. State Initialization: Ensure configuration is loaded.
	_ensure_initialized()

	return _log_file_path


## Returns the absolute OS filesystem path of the current log file.
static func get_absolute_log_file_path() -> String:
	# 1. State Initialization: Ensure configuration is loaded.
	_ensure_initialized()

	return ProjectSettings.globalize_path(_log_file_path)


## Flushes any buffered file writes immediately to disk.
static func flush() -> void:
	if _file_handle != null:
		_file_handle.flush()
	_unflushed_lines = 0
	_last_flush_ms = Time.get_ticks_msec()


## Closes the active log file handle.
static func close() -> void:
	# 1. File Cleanup: Safely closes and releases the active file handle.
	_close_file()


## Resets all logger state, config cache, and file handles (for unit tests and reload).
static func reset_state() -> void:
	# 1. File Cleanup: Close open file handle.
	_close_file()

	_initialized = false
	_printed_startup_path = false
	_subsystem_flags.clear()
	_log_file_path = "user://logs/debug.log"
	_log_to_file = true
	_log_to_console = false
	_unflushed_lines = 0
	_last_flush_ms = 0


# ===================
# Auxiliary Functions
# ===================

static func _ensure_initialized() -> void:
	## Auxiliary: Loads GameConfig settings if not initialized.
	if _initialized:
		return
	_initialized = true

	# 1. Config Loading: Read settings from game_config.tres.
	_load_config_settings()


static func _load_config_settings() -> void:
	## Auxiliary: Loads debug logging values from GameConfig resource.
	var cfg := ResourceLoader.load(_CONFIG_PATH) as GameConfig
	if cfg != null:
		_log_to_file = cfg.log_to_file
		_log_to_console = cfg.log_to_console
		if not cfg.log_file_path.is_empty():
			_log_file_path = cfg.log_file_path
		_subsystem_flags[&"colonist"] = cfg.colonist_debug_logging
	else:
		_subsystem_flags[&"colonist"] = true


static func _open_log_file() -> void:
	## Auxiliary: Creates parent directories and opens the target log file for appending.
	var parent_dir: String = _log_file_path.get_base_dir()
	if not parent_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(parent_dir)

	_file_handle = FileAccess.open(_log_file_path, FileAccess.READ_WRITE)
	if _file_handle == null:
		_file_handle = FileAccess.open(_log_file_path, FileAccess.WRITE)
	else:
		_file_handle.seek_end()

	if not _printed_startup_path and _file_handle != null:
		_printed_startup_path = true
		print("[DebugLogger] Logging enabled -> %s" % ProjectSettings.globalize_path(_log_file_path))


static func _format_entry(subsystem: StringName, message: String) -> String:
	## Auxiliary: Constructs standardized timestamped log line.
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var ms: int = Time.get_ticks_msec() % 1000
	var time_str := "%04d-%02d-%02d %02d:%02d:%02d.%03d" % [
		dt.year, dt.month, dt.day,
		dt.hour, dt.minute, dt.second,
		ms
	]
	return "[%s] [%s] %s" % [time_str, str(subsystem).to_upper(), message]


static func _write_to_file(entry_line: String) -> void:
	## Auxiliary: Appends entry line to open file handle and periodically flushes.
	if not _log_to_file:
		return
	if _file_handle == null:
		# 1. File Reconnect: Attempt to reopen file handle if missing.
		_open_log_file()

	if _file_handle != null:
		_file_handle.store_line(entry_line)
		_unflushed_lines += 1
		var now: int = Time.get_ticks_msec()
		if _unflushed_lines >= _FLUSH_THRESHOLD_LINES or (now - _last_flush_ms) >= _FLUSH_INTERVAL_MS:
			_file_handle.flush()
			_unflushed_lines = 0
			_last_flush_ms = now


static func _write_to_console(entry_line: String) -> void:
	## Auxiliary: Prints entry line to standard console output.
	if _log_to_console:
		print(entry_line)


static func _close_file() -> void:
	## Auxiliary: Flushes and releases the active FileAccess handle.
	if _file_handle != null:
		_file_handle.flush()
		_file_handle.close()
		_file_handle = null
	_unflushed_lines = 0
	_last_flush_ms = 0
