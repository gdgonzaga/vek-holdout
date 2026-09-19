class_name NightRaidController
extends Node
## Night raid orchestrator and spawner (ARCH raids.md).
## Manages night raid timing, evaluates dynamic spawn pacing via GameConfig curves,
## and spawns hostile entities radially around the active player on the terrain
## surface, picking an enemy type per spawn via weighted random selection over
## GameConfig.enemy_pool.

const _DEFAULT_CONFIG_PATH: String = "res://data/game_config.tres"
const _MAX_SPAWN_ATTEMPTS: int = 5
const _HOURS_PER_DAY: float = 24.0
const _MINUTES_PER_HOUR: float = 60.0
const _SECONDS_PER_MINUTE: float = 60.0
const _ELEVATION_SPAWN_OFFSET: float = 1.0

@export var config_path: String = _DEFAULT_CONFIG_PATH

var map: Map = null
var config: GameConfig = null
var raid_active: bool = false

var _spawn_accumulator: float = 0.0
var _cached_curve_mean: float = 1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	
	# 1. Config Resolution: Loads engine and raid configuration resource from disk.
	_load_config()


func _process(delta: float) -> void:
	if GameState.paused or map == null or config == null:
		return

	# 1. Clock Resolution: Computes current fractional in-game hour from time system.
	var current_hour: float = _resolve_current_in_game_hour()

	# 2. Window State Resolution: Determines whether current hour falls within night raid window.
	var should_be_active: bool = _is_hour_in_night_window(
		current_hour,
		config.spawn_start_hour,
		config.spawn_end_hour
	)

	# 3. Lifecycle Transition: Handles entering and exiting active raid state and emits signals.
	_update_raid_lifecycle(should_be_active)

	if not raid_active:
		return

	# 4. Progress Evaluation: Calculates normalized [0.0, 1.0] night duration progress.
	var progress: float = _calculate_night_progress(
		current_hour,
		config.spawn_start_hour,
		config.spawn_end_hour
	)

	# 5. Spawn Rate Sampling: Calculates instantaneous spawn rate per second scaled by pacing curve.
	var rate_per_sec: float = _evaluate_spawn_rate_per_second(
		config.spawns_per_minute,
		config.spawn_rate_curve,
		progress,
		_cached_curve_mean
	)

	# 6. Budget Processing: Accumulates fractional spawn quotas and generates enemy entities.
	_process_spawn_budget(delta, rate_per_sec)


# =============================================================================
# Primary Orchestration
# =============================================================================

func _load_config() -> void:
	## Auxiliary: Loads the GameConfig resource or instantiates a default fallback.
	if ResourceLoader.exists(config_path):
		config = load(config_path) as GameConfig
	if config == null:
		config = GameConfig.new()


func _update_raid_lifecycle(should_be_active: bool) -> void:
	## Auxiliary: Transitions active raid status and emits EventBus lifecycle signals.
	if should_be_active and not raid_active:
		raid_active = true
		_spawn_accumulator = 0.0

		# 1. Curve Pre-calculation: Resolves the curve mean to normalize spawn rates over the night.
		var curve: Curve = config.spawn_rate_curve if config != null else null
		_cached_curve_mean = _calculate_curve_mean(curve)

		EventBus.raid_started.emit({"day": GameState.current_day})
	elif not should_be_active and raid_active:
		raid_active = false
		_spawn_accumulator = 0.0
		EventBus.raid_ended.emit({"day": GameState.current_day})


func _process_spawn_budget(delta: float, rate_per_sec: float) -> void:
	## Auxiliary: Increments spawn budget and triggers enemy spawn calls on integer thresholds.
	_spawn_accumulator += delta * rate_per_sec
	#print("Accumulator: %s | delta: %s | rate: %s" % [_spawn_accumulator, delta, rate_per_sec])
	while _spawn_accumulator >= 1.0:
		_spawn_accumulator -= 1.0

		# 1. Hostile Generation: Spawns one enemy at a valid radial terrain coordinate around player.
		_spawn_raid_enemy()


func _spawn_raid_enemy() -> bool:
	## Auxiliary: Finds valid ground position, instantiates enemy, and wires navigation.
	var player := GameState.get_local_player() as Node3D
	if player == null or map == null:
		return false

	# 1. Position Resolution: Finds a valid raycast ground coordinate around the player.
	var spawn_pos: Vector3 = _find_valid_spawn_position(player.global_position)
	if is_nan(spawn_pos.y):
		return false

	# 2. Entity Creation: Spawns the enemy scene inside the map's enemy container.
	var enemy: EnemyBase = _instantiate_enemy(spawn_pos)
	if enemy == null:
		return false
	print("spawned enemy")

	# 3. Pathfinding Wiring: Configures walkability and terrain hints on the enemy pathfinder.
	_wire_enemy(enemy)
	return true


# =============================================================================
# Auxiliary Functions (Narrative Flow / Step-Down)
# =============================================================================

func _resolve_current_in_game_hour() -> float:
	## Auxiliary: Calculates floating-point hour (0.0 to 24.0) from TimeSystem day fraction.
	var day_fraction: float = TimeSystem.get_time_of_day_fraction()
	var raw_hours: float = (day_fraction * _HOURS_PER_DAY) + TimeSystem.START_HOUR_OFFSET
	return fmod(raw_hours, _HOURS_PER_DAY)


func _is_hour_in_night_window(hour: float, start_h: float, end_h: float) -> bool:
	## Auxiliary: Checks if an hour is inside the raid window, handling midnight rollover.
	if start_h <= end_h:
		return hour >= start_h and hour < end_h
	return hour >= start_h or hour < end_h


func _calculate_night_progress(hour: float, start_h: float, end_h: float) -> float:
	## Auxiliary: Returns normalized progress [0.0, 1.0] from raid start to raid end.
	var total_span: float = end_h - start_h if end_h >= start_h else (_HOURS_PER_DAY - start_h) + end_h
	if total_span <= 0.0:
		return 0.0
	var elapsed: float = hour - start_h if hour >= start_h else (_HOURS_PER_DAY - start_h) + hour
	return clampf(elapsed / total_span, 0.0, 1.0)


func _evaluate_spawn_rate_per_second(
	base_per_min: float,
	curve: Curve,
	progress: float,
	curve_mean: float = -1.0
) -> float:
	## Auxiliary: Evaluates instantaneous spawn frequency scaled by normalized distribution curve.
	var base_rate_per_sec: float = base_per_min / _SECONDS_PER_MINUTE
	if curve == null:
		return maxf(0.0, base_rate_per_sec)

	var mean: float = curve_mean
	if mean <= 0.0:
		# 1. Curve Normalization: Resolves mean curve value to ensure total spawn quota is preserved.
		mean = _calculate_curve_mean(curve)

	var raw_multiplier: float = curve.sample_baked(progress)
	var normalized_multiplier: float = raw_multiplier / mean
	return maxf(0.0, base_rate_per_sec * normalized_multiplier)


func _calculate_curve_mean(curve: Curve) -> float:
	## Auxiliary: Samples the curve across [0.0, 1.0] to compute its mean value for normalization.
	if curve == null:
		return 1.0
	const SAMPLE_COUNT: int = 16
	var sum: float = 0.0
	for i in range(SAMPLE_COUNT):
		var t: float = float(i) / float(SAMPLE_COUNT - 1)
		sum += curve.sample_baked(t)
	var mean: float = sum / float(SAMPLE_COUNT)
	return mean if mean > 0.0001 else 1.0


func _find_valid_spawn_position(player_pos: Vector3) -> Vector3:
	## Auxiliary: Samples random radial points around player and queries terrain surface height.
	for i in range(_MAX_SPAWN_ATTEMPTS):
		# 1. Radial Sampling: Computes polar coordinate offset within configured distance limits.
		var offset: Vector2 = _sample_radial_offset(config.spawn_distance_min, config.spawn_distance_max)
		var target_x: float = player_pos.x + offset.x
		var target_z: float = player_pos.z + offset.y

		# 2. Elevation Query: Downward physics raycast to detect highest terrain surface.
		var ground_y: float = map.ground_height_at(target_x, target_z)
		if not is_nan(ground_y):
			return Vector3(target_x, ground_y + _ELEVATION_SPAWN_OFFSET, target_z)
	return Vector3(NAN, NAN, NAN)


func _sample_radial_offset(min_dist: float, max_dist: float) -> Vector2:
	## Auxiliary: Generates uniform random angle and distance vector on horizontal plane.
	var angle: float = _rng.randf_range(0.0, TAU)
	var dist: float = _rng.randf_range(min_dist, max_dist)
	return Vector2(cos(angle) * dist, sin(angle) * dist)


func _instantiate_enemy(pos: Vector3) -> EnemyBase:
	## Auxiliary: Instantiates enemy prototype and parents it under map enemy container.
	var container := map.get_enemy_container()
	if container == null:
		return null

	# 1. Enemy Type Selection: Weighted-random pick over the configured raid spawn pool.
	var scene: PackedScene = _select_weighted_enemy_scene(config.enemy_pool, _rng)
	if scene == null:
		return null

	var node: Node = scene.instantiate()
	var enemy := node as EnemyBase
	if enemy == null:
		node.queue_free()
		return null
	enemy.global_position = pos
	container.add_child(enemy)
	return enemy


func _select_weighted_enemy_scene(pool: Array[RaidSpawnEntry], rng: RandomNumberGenerator) -> PackedScene:
	## Auxiliary: Resolves a pool entry's scene via weighted random index selection.
	if pool.is_empty():
		return null
	var weights: Array[float] = []
	for entry in pool:
		weights.append(entry.weight)

	# 1. Index Roll: Rolls a cumulative-weight index across the pool's weights.
	var index: int = _pick_weighted_index(weights, rng)
	if index < 0:
		return null
	return pool[index].enemy_scene


func _pick_weighted_index(weights: Array[float], rng: RandomNumberGenerator) -> int:
	## Auxiliary: Rolls a cumulative-weight index; returns -1 when total weight is non-positive.
	var total: float = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return -1

	var roll: float = rng.randf_range(0.0, total)
	var cumulative: float = 0.0
	for i in range(weights.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return i
	return weights.size() - 1


func _wire_enemy(enemy: EnemyBase) -> void:
	## Auxiliary: Injects map walkability and surface stand hints into enemy pathfinder.
	if enemy == null or map == null:
		return

	# 1. Pathfinder Wiring: Delegates walkability and stand hint setup to MapWiring helper.
	MapWiring.wire_enemy_pathfinder(enemy, map)
