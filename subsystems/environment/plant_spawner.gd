class_name PlantSpawner
extends Node
## Dynamic flora regeneration system for colony maps.
##
## Periodically spawns trees and vegetation across the map throughout each
## in-game day based on MapDef flora parameters. Spawns are spaced evenly
## across the day cycle, capped at flora_spawn_cap, and checked against terrain
## slope, player proximity, and tree-to-tree spacing invariants.

const DEFAULT_MAX_SLOPE_DEG := 25.0
const DEFAULT_LOOP_LENGTH_SEC := 1800.0 # 30 real minutes

var _map: Map = null
var _map_def: MapDef = null
var _furniture_layer: FurnitureLayer = null
var _furniture_container: Node3D = null

var _cached_flora_count: int = 0
var _spawn_timer: float = 0.0
var _spawn_interval: float = 0.0
var _target_tag: String = "live_flora"
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# 1. Event Subscriptions: Connect to day rollover and furniture placement/removal signals.
	_connect_events()


func _process(delta: float) -> void:
	if _map_def == null or _map_def.flora_spawns_per_day <= 0:
		return
	if GameState.paused:
		return
	if _spawn_interval <= 0.0:
		# 2. Interval Calculation: Computes timer interval for daily spawns.
		_recalculate_spawn_interval()
	
	_spawn_timer += delta
	if _spawn_timer >= _spawn_interval:
		_spawn_timer = 0.0
		# 3. Scheduled Spawn Execution: Trigger a flora spawn cycle.
		attempt_spawn()


## Inject map references and configure flora spawner parameters.
func setup(map: Map, map_def: MapDef, furniture_layer: FurnitureLayer) -> void:
	_map = map
	_map_def = map_def
	_furniture_layer = furniture_layer
	if _map != null:
		_furniture_container = _map.get_furniture_container()
	
	# 1. Initial State Sync: Scans live furniture container to initialize count.
	_sync_flora_count()
	# 2. Interval Calculation: Derives timer cadence based on day length and daily quota.
	_recalculate_spawn_interval()


## Populates initial flora on a fresh map load up to flora_spawn_cap.
## Uses a total attempt budget pool of (target_cap * max_attempts_per_flora).
## Returns the number of placed flora items during this pass.
func populate_initial_flora() -> int:
	if _map == null or _map_def == null or _furniture_layer == null:
		return 0
	if _map_def.flora_palette.is_empty() or _map_def.flora_spawn_cap <= 0:
		return 0

	var initial_placed: int = 0
	var total_attempts: int = 0
	var max_total_attempts: int = _map_def.flora_spawn_cap * maxi(1, _map_def.flora_max_spawn_attempts)

	while get_live_flora_count() < _map_def.flora_spawn_cap and total_attempts < max_total_attempts:
		total_attempts += 1
		# 1. Single Coordinate Attempt: Probes one random coordinate for placement.
		var spawned := _try_spawn_at_random_location()
		if spawned:
			initial_placed += 1

	return initial_placed


## Attempts to spawn a single flora instance on a valid ground coordinate.
## Returns true if a tree/plant was successfully placed.
func attempt_spawn() -> bool:
	if _map == null or _map_def == null or _furniture_layer == null:
		return false
	if _map_def.flora_palette.is_empty():
		return false
	
	# 1. Cap Evaluation: Verify active flora count has not reached the configured maximum.
	if get_live_flora_count() >= _map_def.flora_spawn_cap:
		return false

	var attempts: int = 0
	var max_attempts: int = maxi(1, _map_def.flora_max_spawn_attempts)

	while attempts < max_attempts:
		attempts += 1
		# 2. Single Coordinate Attempt: Probes one random coordinate for placement.
		var spawned := _try_spawn_at_random_location()
		if spawned:
			return true

	return false


## Returns the verified number of active flora nodes currently in the map.
func get_live_flora_count() -> int:
	if _furniture_container == null:
		return _cached_flora_count
	var count: int = 0
	for child in _furniture_container.get_children():
		if child is Furniture and not child.is_queued_for_deletion():
			# 1. Tag Check: Verify whether furniture instance carries flora tag or is in palette.
			if _is_flora_node(child as Furniture):
				count += 1
	_cached_flora_count = count
	return count


# ===================
# Auxiliary Functions
# ===================

func _try_spawn_at_random_location() -> bool:
	## Auxiliary: Samples a random coordinate, validates constraints, and places flora if valid.
	if _map == null or _map_def == null or _furniture_layer == null:
		return false
	var bounds: AABB = _map.get_world_bounds()
	var player_pos: Vector3 = _map_def.player_spawn
	var min_dist_sq: float = _map_def.flora_min_distance * _map_def.flora_min_distance

	# 1. Coordinate Sampling: Pick random horizontal position inside world bounds.
	var sample_xz: Vector2 = _sample_random_coordinate(bounds)
	
	# 2. Player Proximity Check: Ensure sampled point is not too close to player spawn.
	if _is_too_close_to_point(sample_xz, Vector2(player_pos.x, player_pos.z), min_dist_sq):
		return false
	
	# 3. Existing Flora Proximity Check: Ensure sampled point is spaced away from other trees.
	if _is_too_close_to_existing_flora(sample_xz, min_dist_sq):
		return false
	
	# 4. Ground Height Query: Query terrain surface height at column.
	var ground_y: float = _query_ground_height(sample_xz.x, sample_xz.y)
	if is_nan(ground_y):
		return false
	
	# 5. Slope Evaluation: Estimate terrain normal to reject steep cliff faces.
	var normal: Vector3 = _estimate_surface_normal(sample_xz.x, sample_xz.y, ground_y)
	if not _is_slope_acceptable(normal, DEFAULT_MAX_SLOPE_DEG):
		return false
	
	# 6. Def Selection: Pick random flora definition from the configured palette.
	var chosen_def: FurnitureDef = _pick_random_flora_def()
	if chosen_def == null:
		return false
	
	var anchor := Vector3i(int(floor(sample_xz.x)), int(round(ground_y)), int(floor(sample_xz.y)))
	var yaw: int = _rng.randi_range(0, 3)
	
	# 7. World Placement: Spawn the furniture node via FurnitureLayer.
	var spawned_node: Node3D = _furniture_layer.spawn(chosen_def, anchor, yaw)
	if spawned_node != null:
		_cached_flora_count += 1
		return true
	
	return false


func _connect_events() -> void:
	## Auxiliary: Wires EventBus signals for day transitions and furniture lifecycle.
	EventBus.day_rolled_over.connect(_on_day_rolled_over)
	EventBus.furniture_placed.connect(_on_furniture_placed)
	EventBus.furniture_removed.connect(_on_furniture_removed)


func _on_day_rolled_over(_new_day: int) -> void:
	## Auxiliary: Handles day boundary transitions by resetting daily spawn timer.
	_spawn_timer = 0.0
	# 1. State Reconciliation: Sync flora count cache with live container on new day.
	_sync_flora_count()


func _on_furniture_placed(def_id: String, _anchor: Vector3i) -> void:
	## Auxiliary: Increments flora count cache if placed furniture matches flora palette.
	if _is_palette_def_id(def_id):
		_cached_flora_count += 1


func _on_furniture_removed(def_id: String, _anchor: Vector3i) -> void:
	## Auxiliary: Decrements flora count cache if removed furniture matches flora palette.
	if _is_palette_def_id(def_id):
		_cached_flora_count = maxi(0, _cached_flora_count - 1)


func _sync_flora_count() -> void:
	## Auxiliary: Scans the container to ensure cached count matches live hierarchy.
	_cached_flora_count = get_live_flora_count()


func _recalculate_spawn_interval() -> void:
	## Auxiliary: Calculates spawn tick interval in seconds based on day length.
	if _map_def == null or _map_def.flora_spawns_per_day <= 0:
		_spawn_interval = 0.0
		return
	var loop_len: float = DEFAULT_LOOP_LENGTH_SEC
	var game_config: GameConfig = load("res://data/game_config.tres") as GameConfig
	if game_config != null:
		loop_len = game_config.loop_length_minutes * 60.0
	_spawn_interval = loop_len / float(_map_def.flora_spawns_per_day)


func _sample_random_coordinate(bounds: AABB) -> Vector2:
	## Auxiliary: Generates uniform random 2D coordinate within map bounds with a 2m margin.
	const MARGIN := 2.0
	var min_x := bounds.position.x + MARGIN
	var max_x := bounds.position.x + bounds.size.x - MARGIN
	var min_z := bounds.position.z + MARGIN
	var max_z := bounds.position.z + bounds.size.z - MARGIN
	return Vector2(
		_rng.randf_range(min_x, max_x),
		_rng.randf_range(min_z, max_z)
	)


func _is_too_close_to_point(p1: Vector2, p2: Vector2, min_dist_sq: float) -> bool:
	## Auxiliary: Computes squared 2D distance to check proximity.
	var dx := p1.x - p2.x
	var dy := p1.y - p2.y
	return (dx * dx + dy * dy) < min_dist_sq


func _is_too_close_to_existing_flora(sample_xz: Vector2, min_dist_sq: float) -> bool:
	## Auxiliary: Checks whether candidate coordinate is within minimum distance of existing trees.
	if _furniture_container == null:
		return false
	for child in _furniture_container.get_children():
		if child is Furniture and not child.is_queued_for_deletion():
			var f: Furniture = child as Furniture
			# 1. Flora Filter: Inspect only nodes identified as flora.
			if _is_flora_node(f):
				var tree_pos := Vector2(f.global_position.x, f.global_position.z)
				if _is_too_close_to_point(sample_xz, tree_pos, min_dist_sq):
					return true
	return false


func _query_ground_height(x: float, z: float) -> float:
	## Auxiliary: Queries map terrain surface height at column (x, z).
	if _map == null:
		return NAN
	var smooth := _map.get_smooth_grid()
	if smooth != null and is_instance_valid(smooth) and smooth.terrain_gen != null:
		var normal_out: Array = []
		var gy: float = smooth.height_at(x, z, normal_out)
		if not is_nan(gy):
			return gy
		if smooth.has_method("_pristine_height"):
			return smooth._pristine_height(int(floor(x)), int(floor(z)))
	return _map.ground_height_at(x, z)


func _estimate_surface_normal(x: float, z: float, center_y: float) -> Vector3:
	## Auxiliary: Calculates terrain surface normal using finite differences.
	if _map == null or is_nan(center_y):
		return Vector3.UP
	var delta: float = 0.5
	# 1. Offset Height Queries: Query 4-directional neighboring heights around column.
	var h_px: float = _query_ground_height(x + delta, z)
	var h_nx: float = _query_ground_height(x - delta, z)
	var h_pz: float = _query_ground_height(x, z + delta)
	var h_nz: float = _query_ground_height(x, z - delta)
	if is_nan(h_px) or is_nan(h_nx) or is_nan(h_pz) or is_nan(h_nz):
		return Vector3.UP
	var dx := (h_px - h_nx) / (2.0 * delta)
	var dz := (h_pz - h_nz) / (2.0 * delta)
	return Vector3(-dx, 1.0, -dz).normalized()


func _is_slope_acceptable(normal: Vector3, max_slope_deg: float) -> bool:
	## Auxiliary: Checks if surface normal inclination is within walkable/plantable slope limit.
	var slope_deg := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
	return slope_deg <= max_slope_deg


func _pick_random_flora_def() -> FurnitureDef:
	## Auxiliary: Selects a FurnitureDef from the configured flora palette.
	if _map_def == null or _map_def.flora_palette.is_empty():
		return null
	var idx := _rng.randi_range(0, _map_def.flora_palette.size() - 1)
	return _map_def.flora_palette[idx]


func _is_flora_node(furniture: Furniture) -> bool:
	## Auxiliary: Identifies whether a Furniture node represents flora via tag or palette.
	if furniture == null:
		return false
	if furniture.has_tag(_target_tag):
		return true
	# 1. Palette Fallback: Check if definition id matches any entry in flora palette.
	return _is_palette_def_id(furniture.def_id)


func _is_palette_def_id(def_id: String) -> bool:
	## Auxiliary: Checks if a def_id string exists in the map's flora palette.
	if _map_def == null or def_id == "":
		return false
	for entry in _map_def.flora_palette:
		if entry != null and entry.id == def_id:
			return true
	return false
