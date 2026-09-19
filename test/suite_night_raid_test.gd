extends GdUnitTestSuite
## Test suite for NightRaidController and nocturnal spawn logic invariants.

var _saved_player: Node = null


func before_test() -> void:
	_saved_player = GameState.get_local_player()


func after_test() -> void:
	GameState.set_local_player(_saved_player)


func test_night_window_evaluation_across_midnight() -> void:
	var controller: NightRaidController = auto_free(NightRaidController.new())
	
	# Crossing midnight: 21:00 to 04:30
	assert_bool(controller._is_hour_in_night_window(20.9, 21.0, 4.5)).is_false()
	assert_bool(controller._is_hour_in_night_window(21.0, 21.0, 4.5)).is_true()
	assert_bool(controller._is_hour_in_night_window(23.5, 21.0, 4.5)).is_true()
	assert_bool(controller._is_hour_in_night_window(0.0, 21.0, 4.5)).is_true()
	assert_bool(controller._is_hour_in_night_window(2.0, 21.0, 4.5)).is_true()
	assert_bool(controller._is_hour_in_night_window(4.49, 21.0, 4.5)).is_true()
	assert_bool(controller._is_hour_in_night_window(4.5, 21.0, 4.5)).is_false()
	assert_bool(controller._is_hour_in_night_window(12.0, 21.0, 4.5)).is_false()

	# Non-crossing daytime window: 08:00 to 16:00
	assert_bool(controller._is_hour_in_night_window(7.9, 8.0, 16.0)).is_false()
	assert_bool(controller._is_hour_in_night_window(10.0, 8.0, 16.0)).is_true()
	assert_bool(controller._is_hour_in_night_window(16.0, 8.0, 16.0)).is_false()


func test_night_progress_calculation() -> void:
	var controller: NightRaidController = auto_free(NightRaidController.new())
	
	# Window spanning 8 hours: 21.0 to 05.0
	var p_start: float = controller._calculate_night_progress(21.0, 21.0, 5.0)
	assert_float(p_start).is_equal_approx(0.0, 0.001)

	var p_mid: float = controller._calculate_night_progress(1.0, 21.0, 5.0)
	assert_float(p_mid).is_equal_approx(0.5, 0.001)

	var p_end: float = controller._calculate_night_progress(5.0, 21.0, 5.0)
	assert_float(p_end).is_equal_approx(1.0, 0.001)


func test_radial_offset_within_configured_bounds() -> void:
	var controller: NightRaidController = auto_free(NightRaidController.new())
	var min_dist: float = 15.0
	var max_dist: float = 35.0
	
	for i in range(50):
		var offset: Vector2 = controller._sample_radial_offset(min_dist, max_dist)
		var dist: float = offset.length()
		assert_float(dist).is_greater_equal(min_dist - 0.001)
		assert_float(dist).is_less_equal(max_dist + 0.001)


func test_spawn_rate_per_second_evaluation() -> void:
	var controller: NightRaidController = auto_free(NightRaidController.new())
	
	# Base 6.0 spawns per minute -> 0.1 spawns per second without curve
	var rate_flat: float = controller._evaluate_spawn_rate_per_second(6.0, null, 0.5)
	assert_float(rate_flat).is_equal_approx(0.1, 0.001)

	# Dynamic curve with peak of 2.0 and edges of 0.5 (mean is 1.25)
	var curve := Curve.new()
	curve.max_value = 3.0
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(0.5, 2.0))
	curve.add_point(Vector2(1.0, 0.5))
	
	# Peak at progress 0.5: multiplier is 2.0 / 1.25 = 1.6 -> 0.1 * 1.6 = 0.16
	var rate_curved: float = controller._evaluate_spawn_rate_per_second(6.0, curve, 0.5)
	assert_float(rate_curved).is_equal_approx(0.16, 0.01)

	# Edge at progress 0.0: multiplier is 0.5 / 1.25 = 0.4 -> 0.1 * 0.4 = 0.04
	var rate_edge: float = controller._evaluate_spawn_rate_per_second(6.0, curve, 0.0)
	assert_float(rate_edge).is_equal_approx(0.04, 0.01)


func test_normalized_curve_reaches_spawn_threshold() -> void:
	var controller: NightRaidController = auto_free(NightRaidController.new())
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1.0, 0.3))
	
	# 8.75s night duration at 60 fps (525 frames) with 10 spawns per minute
	var total_accumulated: float = 0.0
	var delta: float = 1.0 / 60.0
	var total_frames: int = 525
	var crossed_one: bool = false

	for frame in range(total_frames):
		var progress: float = float(frame) / float(total_frames - 1)
		var rate: float = controller._evaluate_spawn_rate_per_second(10.0, curve, progress)
		total_accumulated += delta * rate
		if total_accumulated >= 1.0:
			crossed_one = true

	# Total accumulated must equal expected total (8.75s * 10 / 60s = ~1.458) and cross 1.0
	assert_bool(crossed_one).is_true()
	assert_float(total_accumulated).is_greater_equal(1.4)


func test_wire_raids_mounts_controller_on_map() -> void:
	var map: Map = auto_free(preload("res://subsystems/maps/map_template.tscn").instantiate() as Map)
	add_child(map)

	var controller := MapWiring.wire_raids(map)
	assert_that(controller).is_not_null()
	assert_that(map.find_child("NightRaidController", true, false)).is_equal(controller)

	# Idempotent call returns existing instance
	var controller_again := MapWiring.wire_raids(map)
	assert_that(controller_again).is_equal(controller)


func test_raid_lifecycle_emits_event_bus_signals() -> void:
	var controller: NightRaidController = auto_free(NightRaidController.new())
	var started_payloads: Array[Dictionary] = []
	var ended_payloads: Array[Dictionary] = []

	var on_started: Callable = func(data: Dictionary) -> void: started_payloads.append(data)
	var on_ended: Callable = func(data: Dictionary) -> void: ended_payloads.append(data)

	EventBus.raid_started.connect(on_started)
	EventBus.raid_ended.connect(on_ended)

	# Transition to active
	controller._update_raid_lifecycle(true)
	assert_bool(controller.raid_active).is_true()
	assert_int(started_payloads.size()).is_equal(1)
	assert_int(ended_payloads.size()).is_equal(0)

	# Transition to inactive
	controller._update_raid_lifecycle(false)
	assert_bool(controller.raid_active).is_false()
	assert_int(started_payloads.size()).is_equal(1)
	assert_int(ended_payloads.size()).is_equal(1)

	EventBus.raid_started.disconnect(on_started)
	EventBus.raid_ended.disconnect(on_ended)


func test_pick_weighted_index_selects_sole_nonzero_weight() -> void:
	var controller: NightRaidController = auto_free(NightRaidController.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	for i in range(20):
		var index: int = controller._pick_weighted_index([0.0, 1.0, 0.0], rng)
		assert_int(index).is_equal(1)


func test_pick_weighted_index_returns_negative_one_for_non_positive_weights() -> void:
	var controller: NightRaidController = auto_free(NightRaidController.new())
	var rng := RandomNumberGenerator.new()

	assert_int(controller._pick_weighted_index([], rng)).is_equal(-1)
	assert_int(controller._pick_weighted_index([0.0, 0.0], rng)).is_equal(-1)


func test_select_weighted_enemy_scene_returns_null_for_empty_pool() -> void:
	var controller: NightRaidController = auto_free(NightRaidController.new())
	var rng := RandomNumberGenerator.new()
	var pool: Array[RaidSpawnEntry] = []

	assert_that(controller._select_weighted_enemy_scene(pool, rng)).is_null()


func test_select_weighted_enemy_scene_returns_single_entry_scene() -> void:
	var controller: NightRaidController = auto_free(NightRaidController.new())
	var rng := RandomNumberGenerator.new()

	var dummy_node: Node = auto_free(Node.new())
	var dummy_scene := PackedScene.new()
	dummy_scene.pack(dummy_node)

	var entry := RaidSpawnEntry.new()
	entry.enemy_scene = dummy_scene
	entry.weight = 1.0
	var pool: Array[RaidSpawnEntry] = [entry]

	assert_that(controller._select_weighted_enemy_scene(pool, rng)).is_equal(dummy_scene)
