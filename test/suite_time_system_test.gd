extends GdUnitTestSuite
## Tests for TimeSystem clock calculations, 24h/12h formatting, and DayNightCycle celestial lighting.

const DayNightCycleScript = preload("res://subsystems/environment/day_night_cycle.gd")

var _saved_time_state: Dictionary = {}


func before_test() -> void:
	_saved_time_state = TimeSystem.serialize()


func after_test() -> void:
	TimeSystem.deserialize(_saved_time_state)


func test_clock_time_at_dawn() -> void:
	TimeSystem.deserialize({"elapsed_in_day": 0.0, "realtime_play_time": 0.0})
	var clock: Vector2i = TimeSystem.get_clock_time()
	assert_int(clock.x).is_equal(6)
	assert_int(clock.y).is_equal(0)
	assert_int(TimeSystem.get_current_hour()).is_equal(6)
	assert_int(TimeSystem.get_current_minute()).is_equal(0)
	assert_str(TimeSystem.get_formatted_clock(true)).is_equal("06:00")
	assert_str(TimeSystem.get_formatted_clock(false)).is_equal("06:00 AM")


func test_clock_time_at_midday() -> void:
	# Fraction 0.25 = 6 hours past 06:00 = 12:00
	var midday_seconds: float = TimeSystem._loop_length_seconds * 0.25
	TimeSystem.deserialize({"elapsed_in_day": midday_seconds, "realtime_play_time": 0.0})
	var clock: Vector2i = TimeSystem.get_clock_time()
	assert_int(clock.x).is_equal(12)
	assert_int(clock.y).is_equal(0)
	assert_str(TimeSystem.get_formatted_clock(true)).is_equal("12:00")
	assert_str(TimeSystem.get_formatted_clock(false)).is_equal("12:00 PM")


func test_clock_time_at_sunset() -> void:
	# Fraction 0.50 = 12 hours past 06:00 = 18:00
	var sunset_seconds: float = TimeSystem._loop_length_seconds * 0.50
	TimeSystem.deserialize({"elapsed_in_day": sunset_seconds, "realtime_play_time": 0.0})
	var clock: Vector2i = TimeSystem.get_clock_time()
	assert_int(clock.x).is_equal(18)
	assert_int(clock.y).is_equal(0)
	assert_str(TimeSystem.get_formatted_clock(true)).is_equal("18:00")
	assert_str(TimeSystem.get_formatted_clock(false)).is_equal("06:00 PM")


func test_clock_time_at_midnight() -> void:
	# Fraction 0.75 = 18 hours past 06:00 = 00:00 (Midnight)
	var midnight_seconds: float = TimeSystem._loop_length_seconds * 0.75
	TimeSystem.deserialize({"elapsed_in_day": midnight_seconds, "realtime_play_time": 0.0})
	var clock: Vector2i = TimeSystem.get_clock_time()
	assert_int(clock.x).is_equal(0)
	assert_int(clock.y).is_equal(0)
	assert_str(TimeSystem.get_formatted_clock(true)).is_equal("00:00")
	assert_str(TimeSystem.get_formatted_clock(false)).is_equal("12:00 AM")


func test_day_night_cycle_initialization() -> void:
	var cycle_scene: PackedScene = load("res://subsystems/environment/day_night_cycle.tscn")
	assert_object(cycle_scene).is_not_null()
	var cycle: Node3D = auto_free(cycle_scene.instantiate()) as Node3D
	assert_object(cycle).is_not_null()
	add_child(cycle)

	var moon: DirectionalLight3D = cycle.get_node("CelestialPivot/Moon") as DirectionalLight3D
	assert_object(moon).is_not_null()
	assert_float(abs(moon.rotation.x)).is_equal_approx(PI, 0.001)


func test_day_night_cycle_at_midday() -> void:
	var midday_seconds: float = TimeSystem._loop_length_seconds * 0.25
	TimeSystem.deserialize({"elapsed_in_day": midday_seconds, "realtime_play_time": 0.0})

	var cycle_scene: PackedScene = load("res://subsystems/environment/day_night_cycle.tscn")
	var cycle: DayNightCycle = auto_free(cycle_scene.instantiate()) as DayNightCycle
	add_child(cycle)
	cycle._process(0.0)

	var sun: DirectionalLight3D = cycle.get_node("CelestialPivot/Sun") as DirectionalLight3D
	var moon: DirectionalLight3D = cycle.get_node("CelestialPivot/Moon") as DirectionalLight3D
	assert_bool(sun.visible).is_true()
	assert_bool(moon.visible).is_false()
	assert_float(cycle._get_sun_elevation()).is_equal_approx(1.0, 0.01)
	assert_float(sun.light_energy).is_equal_approx(cycle.max_sun_energy, 0.01)


func test_day_night_cycle_at_midnight() -> void:
	var midnight_seconds: float = TimeSystem._loop_length_seconds * 0.75
	TimeSystem.deserialize({"elapsed_in_day": midnight_seconds, "realtime_play_time": 0.0})

	var cycle_scene: PackedScene = load("res://subsystems/environment/day_night_cycle.tscn")
	var cycle: DayNightCycle = auto_free(cycle_scene.instantiate()) as DayNightCycle
	add_child(cycle)
	cycle._process(0.0)

	var sun: DirectionalLight3D = cycle.get_node("CelestialPivot/Sun") as DirectionalLight3D
	var moon: DirectionalLight3D = cycle.get_node("CelestialPivot/Moon") as DirectionalLight3D
	assert_bool(sun.visible).is_false()
	assert_bool(moon.visible).is_true()
	assert_float(cycle._get_sun_elevation()).is_equal_approx(-1.0, 0.01)
	assert_float(moon.light_energy).is_equal_approx(cycle.max_moon_energy, 0.01)

