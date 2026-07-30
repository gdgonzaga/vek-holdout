extends Node
## Continuous time advance (ARCH "Subsystem: Core", lines 237, 84).
## Advances the in-game clock at a real-time rate; on crossing a day boundary
## calls GameState.advance_day() and emits day_rolled_over via EventBus. Also
## exposes advance_to_midnight() as the sleep trigger (ARCH line 255).
##
## Day length comes from data/game_config.tres (loop_length_minutes, default 30).
##
## TODO: no continuous time-of-day value is exposed (ARCH has no field for it;
## see TODO.md "Known gaps"). Add when the clock display lands.

const _CONFIG_PATH := "res://data/game_config.tres"

var _loop_length_seconds: float = 30.0 * 60.0   # real seconds per in-game day
var _elapsed_in_day: float = 0.0                  # real seconds accumulated in the current day


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


func _roll_over_day() -> void:
	GameState.advance_day()                              # emits day_changed (direct)
	EventBus.day_rolled_over.emit(GameState.current_day) # cross-scene relay


func _on_day_rolled_over(_new_day: int) -> void:
	# SaveSystem listens to day_rolled_over directly; TimeSystem does not own
	# saving. This hook exists for any time-internal bookkeeping on rollover.
	pass
