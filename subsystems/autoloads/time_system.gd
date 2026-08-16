extends Node
## Continuous time advance (ARCH "Subsystem: Core", lines 237, 84).
## Advances the in-game clock at a real-time rate; on crossing a day boundary
## calls GameState.advance_day() and emits day_rolled_over via EventBus. Also
## exposes advance_to_midnight() as the sleep trigger (ARCH line 255).
##
## Day length comes from data/game_config.tres (loop_length_minutes, default 30).

const _CONFIG_PATH := "res://data/game_config.tres"

var _loop_length_seconds: float = 30.0 * 60.0   # real seconds per in-game day
var _elapsed_in_day: float = 0.0                  # real seconds accumulated in the current day
var _realtime_play_time: float = 0.0              # total unpaused real-time play seconds accumulated


func _ready() -> void:
	var config: GameConfig = load(_CONFIG_PATH)
	if config != null:
		_loop_length_seconds = config.loop_length_minutes * 60.0
	# Autosave hook: midnight triggers the save path even though the body is a
	# stub for now (ARCH line 256).
	EventBus.day_rolled_over.connect(_on_day_rolled_over)


func _process(delta: float) -> void:
	# Pause halts time (full-pause-everywhere, ARCH line 143).
	if GameState.paused:
		return
	_elapsed_in_day += delta
	_realtime_play_time += delta
	if _elapsed_in_day >= _loop_length_seconds:
		_elapsed_in_day = 0.0
		_roll_over_day()


## Sleep trigger: force the day boundary now (ARCH Sleep flow, line 255).
func advance_to_midnight() -> void:
	_elapsed_in_day = 0.0
	_roll_over_day()


## 0.0 (dawn) to ~1.0 (just before midnight) — fraction of the current day.
func get_time_of_day_fraction() -> float:
	return _elapsed_in_day / _loop_length_seconds


## Total elapsed in-game days in decimal representation (e.g. 2.45 days).
func get_elapsed_days() -> float:
	return float(GameState.current_day - 1) + get_time_of_day_fraction()


## Total real-time play time in seconds accumulated across the session.
func get_realtime_play_time() -> float:
	return _realtime_play_time


## Total real-time play time formatted as "HH:MM:SS" string.
func get_realtime_play_time_formatted() -> String:
	var total_sec := int(_realtime_play_time)
	var hours := total_sec / 3600
	var mins := (total_sec % 3600) / 60
	var secs := total_sec % 60
	return "%02d:%02d:%02d" % [hours, mins, secs]


# --- SaveSystem contract -----------------------------------------------------
# Only the within-day progress and realtime play time are run state.
# _loop_length_seconds is config (derived from data/game_config.tres), so it is not persisted.

func serialize() -> Dictionary:
	return {
		"elapsed_in_day": _elapsed_in_day,
		"realtime_play_time": _realtime_play_time
	}


func deserialize(data: Dictionary) -> void:
	_elapsed_in_day = float(data.get("elapsed_in_day", 0.0))
	_realtime_play_time = float(data.get("realtime_play_time", 0.0))


func _roll_over_day() -> void:
	GameState.advance_day()                              # emits day_changed (direct)
	EventBus.day_rolled_over.emit(GameState.current_day) # cross-scene relay


func _on_day_rolled_over(_new_day: int) -> void:
	# SaveSystem listens to day_rolled_over directly; TimeSystem does not own
	# saving. This hook exists for any time-internal bookkeeping on rollover.
	pass
