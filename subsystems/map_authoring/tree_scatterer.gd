class_name TreeScatterer
extends RefCounted
## Procedural tree and harvestable flora scattering utility for authored maps.
##
## Scatters free-standing furniture definitions (e.g. tree1) across map terrain
## using a 3-layer density model:
##   1. Macro clustering (2D FastNoiseLite for natural forest groves and clearings).
##   2. Micro spacing (minimum distance gate between tree trunks).
##   3. Target count / density budget with slope and spawn clearance gating.
##
## Authored trees are registered via FurnitureAuthoring into SpawnPoints in
## map.tscn, making them visible in the editor, editable in F4 Furniture mode,
## and persisted upon saving.

const DEFAULT_TREE_TYPES: Array[Dictionary] = [
	{"id": "tree1", "weight": 1.0},
]

const DENSITY_SPARSE: int = 30
const DENSITY_NORMAL: int = 75
const DENSITY_DENSE: int = 150

const DEFAULT_MIN_DISTANCE: float = 4.5
const DEFAULT_MAX_SLOPE_DEG: float = 25.0
const DEFAULT_PLAYER_EXCLUSION_RADIUS: float = 8.0
const DEFAULT_RADIUS: float = 64.0
const DEFAULT_CLUSTER_FREQUENCY: float = 0.015
const DEFAULT_CLUSTER_THRESHOLD: float = -0.1


## Scatter trees onto the map's terrain surface and register them into
## the map's authored FurnitureAuthoring layer. Returns the number of placed trees.
static func scatter_trees(
	map: Map,
	furniture_auth: FurnitureAuthoring,
	tree_types: Array[Dictionary] = DEFAULT_TREE_TYPES,
	config: Dictionary = {}
) -> int:
	if map == null or furniture_auth == null:
		push_error("TreeScatterer.scatter_trees: map or furniture_auth is null")
		return 0

	# 1. Resolve and cache FurnitureDef resources with cumulative weights.
	var def_entries: Array[Dictionary] = []
	var total_weight: float = 0.0
	for entry in tree_types:
		var def_id: String = entry.get("id", "")
		var weight: float = float(entry.get("weight", entry.get("rate", 1.0)))
		if def_id.is_empty() or weight <= 0.0:
			continue
		# TODO: find a way to use resources instead. ID to filename mapping is brittle.
		var path := "res://data/furniture/%s.tres" % def_id
		if not ResourceLoader.exists(path):
			push_warning("TreeScatterer: furniture def not found at '%s'" % path)
			continue
		var def: FurnitureDef = load(path) as FurnitureDef
		if def == null:
			push_warning("TreeScatterer: failed to load FurnitureDef from '%s'" % path)
			continue
		total_weight += weight
		def_entries.append({
			"def": def,
			"cumulative_weight": total_weight,
		})

	if def_entries.is_empty() or total_weight <= 0.0:
		push_warning("TreeScatterer: no valid tree definitions available to scatter")
		return 0

	# 2. Extract configuration parameters.
	var target_count: int = int(config.get("target_count", DENSITY_NORMAL))
	var min_distance: float = float(config.get("min_distance", DEFAULT_MIN_DISTANCE))
	var min_distance_sq: float = min_distance * min_distance
	var max_slope_deg: float = float(config.get("max_slope_deg", DEFAULT_MAX_SLOPE_DEG))
	var player_radius: float = float(config.get("player_exclusion_radius", DEFAULT_PLAYER_EXCLUSION_RADIUS))
	var player_radius_sq: float = player_radius * player_radius
	var radius: float = float(config.get("radius", DEFAULT_RADIUS))
	var cluster_freq: float = float(config.get("cluster_frequency", DEFAULT_CLUSTER_FREQUENCY))
	var cluster_thresh: float = float(config.get("cluster_threshold", DEFAULT_CLUSTER_THRESHOLD))
	var rng_seed: int = int(config.get("seed", 0))

	var rng := RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

	var cluster_noise := FastNoiseLite.new()
	cluster_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cluster_noise.seed = rng.randi()
	cluster_noise.frequency = cluster_freq

	# 3. Locate player spawn position to respect exclusion clearance.
	var player_spawn_pos := Vector3.ZERO
	var spawn_points := map.get_node_or_null("SpawnPoints")
	if spawn_points != null:
		var pmarker := spawn_points.get_node_or_null("PlayerSpawn") as Marker3D
		if pmarker != null:
			player_spawn_pos = pmarker.global_position

	# 4. Placement iteration.
	var placed_positions: Array[Vector2] = []
	var placed_count: int = 0
	var max_attempts: int = target_count * 40
	var attempts: int = 0

	var smooth_grid := map.get_smooth_grid()

	while placed_count < target_count and attempts < max_attempts:
		attempts += 1

		# Uniform sampling within circle.
		var r := radius * sqrt(rng.randf())
		var theta := rng.randf() * TAU
		var x := r * cos(theta)
		var z := r * sin(theta)

		# Check player spawn exclusion clearance.
		var dx_player := x - player_spawn_pos.x
		var dz_player := z - player_spawn_pos.z
		if (dx_player * dx_player + dz_player * dz_player) < player_radius_sq:
			continue

		# Macro clustering check (forest groves vs meadows).
		var noise_val := cluster_noise.get_noise_2d(x, z)
		if noise_val < cluster_thresh:
			continue

		# Micro spacing check (minimum distance from already placed trees).
		var too_close := false
		for p: Vector2 in placed_positions:
			var dx := x - p.x
			var dz := z - p.y
			if (dx * dx + dz * dz) < min_distance_sq:
				too_close = true
				break
		if too_close:
			continue

		# Surface query & slope check.
		var ground_y := NAN
		var surface_normal := Vector3.UP
		if smooth_grid != null and is_instance_valid(smooth_grid) and smooth_grid.terrain_gen != null:
			var normal_out: Array = []
			ground_y = smooth_grid.height_at(x, z, normal_out)
			if is_nan(ground_y) and smooth_grid.has_method("_pristine_height"):
				ground_y = smooth_grid._pristine_height(int(floor(x)), int(floor(z)))
			if not normal_out.is_empty() and normal_out[0] is Vector3:
				surface_normal = normal_out[0]
			elif not is_nan(ground_y):
				surface_normal = _estimate_surface_normal(map, x, z, ground_y)
		elif map != null:
			ground_y = map.ground_height_at(x, z)
			if is_nan(ground_y):
				# Default ground plane when physics ray is unavailable in unit test context.
				ground_y = 0.0
			else:
				surface_normal = _estimate_surface_normal(map, x, z, ground_y)
		else:
			ground_y = 0.0

		if is_nan(ground_y):
			continue

		var slope_deg := rad_to_deg(acos(clampf(surface_normal.y, -1.0, 1.0)))
		if slope_deg > max_slope_deg:
			continue

		# Grid anchor alignment for FurnitureLayer.
		var anchor := Vector3i(int(floor(x)), int(round(ground_y)), int(floor(z)))
		var yaw_quarters := rng.randi_range(0, 3)

		# Weighted pick from def_entries.
		var roll := rng.randf() * total_weight
		var chosen_def: FurnitureDef = def_entries[0]["def"]
		for item in def_entries:
			if roll <= item["cumulative_weight"]:
				chosen_def = item["def"]
				break

		# Place the marker in SpawnPoints via FurnitureAuthoring.
		var marker := furniture_auth.place(chosen_def, anchor, yaw_quarters)
		if marker != null:
			placed_positions.append(Vector2(x, z))
			placed_count += 1

	return placed_count


## Remove all authored tree markers whose def_id matches any ID in tree_ids.
## Returns the count of removed trees.
static func clear_trees(furniture_auth: FurnitureAuthoring, tree_ids: Array[String] = ["tree1"]) -> int:
	if furniture_auth == null or furniture_auth._spawn_points == null:
		return 0

	var removed_count: int = 0
	var markers_to_remove: Array[Vector3i] = []

	for child in furniture_auth._spawn_points.get_children():
		if child is Marker3D and child.name.begins_with("Furniture_") and not child.is_queued_for_deletion():
			var def_id: String = child.get_meta("def_id", "")
			if def_id in tree_ids:
				var anchor: Vector3i = child.get_meta("anchor", Vector3i())
				markers_to_remove.append(anchor)

	for anchor in markers_to_remove:
		if furniture_auth.remove_at(anchor):
			removed_count += 1

	return removed_count


## Estimate terrain surface normal via finite difference when normal_out is unavailable.
static func _estimate_surface_normal(map: Map, x: float, z: float, center_y: float) -> Vector3:
	if map == null or is_nan(center_y):
		return Vector3.UP
	var smooth_grid := map.get_smooth_grid()
	var delta: float = 0.5
	var h_px: float = NAN
	var h_nx: float = NAN
	var h_pz: float = NAN
	var h_nz: float = NAN
	if smooth_grid != null and is_instance_valid(smooth_grid) and smooth_grid.terrain_gen != null and smooth_grid.has_method("_pristine_height"):
		h_px = smooth_grid._pristine_height(int(floor(x + delta)), int(floor(z)))
		h_nx = smooth_grid._pristine_height(int(floor(x - delta)), int(floor(z)))
		h_pz = smooth_grid._pristine_height(int(floor(x)), int(floor(z + delta)))
		h_nz = smooth_grid._pristine_height(int(floor(x)), int(floor(z - delta)))
	else:
		h_px = map.ground_height_at(x + delta, z)
		h_nx = map.ground_height_at(x - delta, z)
		h_pz = map.ground_height_at(x, z + delta)
		h_nz = map.ground_height_at(x, z - delta)
	if is_nan(h_px) or is_nan(h_nx) or is_nan(h_pz) or is_nan(h_nz):
		return Vector3.UP
	var dx := (h_px - h_nx) / (2.0 * delta)
	var dz := (h_pz - h_nz) / (2.0 * delta)
	return Vector3(-dx, 1.0, -dz).normalized()
