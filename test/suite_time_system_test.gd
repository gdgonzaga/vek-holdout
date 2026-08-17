extends GdUnitTestSuite

## Unit tests for the TimeSystem autoload: decimal elapsed-days math, realtime
## play-time formatting, and the serialize/deserialize round-trip. TimeSystem
## persists across suites (AGENTS.md), so every touched field is saved and
## restored.

func test_realtime_and_decimal_days() -> void:
	# Store initial time state
	var initial_day: int = GameState.current_day
	var initial_elapsed_in_day: float = TimeSystem._elapsed_in_day
	var initial_realtime: float = TimeSystem._realtime_play_time

	GameState.current_day = 3
	TimeSystem._elapsed_in_day = 450.0 # 450s out of 1800s (30m) = 0.25 day
	TimeSystem._realtime_play_time = 3665.0 # 1h 01m 05s

	# Assert decimal elapsed days: (Day 3 - 1) + 0.25 = 2.25 days
	assert_float(TimeSystem.get_elapsed_days()).is_equal_approx(2.25, 0.01)

	# Assert realtime play time
	assert_float(TimeSystem.get_realtime_play_time()).is_equal(3665.0)
	assert_str(TimeSystem.get_realtime_play_time_formatted()).is_equal("01:01:05")

	# Test serialization & deserialization
	var ser := TimeSystem.serialize()
	assert_float(float(ser.get("realtime_play_time", 0.0))).is_equal(3665.0)

	TimeSystem._realtime_play_time = 0.0
	TimeSystem.deserialize(ser)
	assert_float(TimeSystem.get_realtime_play_time()).is_equal(3665.0)

	# Restore state
	GameState.current_day = initial_day
	TimeSystem._elapsed_in_day = initial_elapsed_in_day
	TimeSystem._realtime_play_time = initial_realtime
