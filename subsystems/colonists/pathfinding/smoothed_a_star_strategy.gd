class_name SmoothedAStarStrategy
extends PathfindingStrategy

## Line-of-Sight (LOS) Smoothed Voxel A* pathfinder.
##
## Performs an 8-way (or 4-way) grid search to handle obstacles and elevation changes,
## then applies line-of-sight "string pulling" across flat spans. Intermediate waypoints
## across open ground are collapsed into direct straight-line vectors, while strictly
## preserving step climbs (+1), drops (-1..-3), and clearance around wall corners.

const _AStar8WayScript = preload("res://subsystems/colonists/pathfinding/a_star_8_way_strategy.gd")

var _search_strategy: PathfindingStrategy


func _init(base_strategy: PathfindingStrategy = null) -> void:
	if base_strategy != null:
		_search_strategy = base_strategy
	else:
		_search_strategy = _AStar8WayScript.new()


func get_strategy_name() -> String:
	var base_name := _search_strategy.get_strategy_name() if _search_strategy != null else "None"
	return "SmoothedAStar (%s)" % base_name


func find_path(start_cell: Vector3i, target_cell: Vector3i, context: Dictionary) -> Dictionary:
	if _search_strategy == null:
		_search_strategy = _AStar8WayScript.new()
	return _search_strategy.find_path(start_cell, target_cell, context)


func find_path_multi_target(start_cell: Vector3i, targets: Array[Vector3i], context: Dictionary) -> Dictionary:
	if _search_strategy == null:
		_search_strategy = _AStar8WayScript.new()
	return _search_strategy.find_path_multi_target(start_cell, targets, context)


func to_world_waypoints(cells: Array[Vector3i], context: Dictionary) -> Array[Vector3]:
	if cells.is_empty():
		return []
	if cells.size() <= 2:
		var simple_pts: Array[Vector3] = []
		for c in cells:
			simple_pts.append(Vector3(c) + CELL_HALF)
		return simple_pts

	var is_walkable: Callable = context.get("is_walkable", Callable())
	if not is_walkable.is_valid():
		var raw_pts: Array[Vector3] = []
		for c in cells:
			raw_pts.append(Vector3(c) + CELL_HALF)
		return raw_pts

	var smoothed: Array[Vector3] = []
	smoothed.append(Vector3(cells[0]) + CELL_HALF)

	var anchor_idx := 0
	var n := cells.size()

	while anchor_idx < n - 1:
		var furthest_idx := anchor_idx + 1

		# Search backwards from the end of the path for the furthest reachable waypoint
		for candidate_idx in range(n - 1, anchor_idx, -1):
			# Vertical changes require explicit waypoint anchors for StepClimber / drop physics
			if not _is_flat_segment(cells, anchor_idx, candidate_idx):
				continue

			if _has_line_of_sight(cells[anchor_idx], cells[candidate_idx], is_walkable):
				furthest_idx = candidate_idx
				break

		smoothed.append(Vector3(cells[furthest_idx]) + CELL_HALF)
		anchor_idx = furthest_idx

	return smoothed


static func _is_flat_segment(cells: Array[Vector3i], start_i: int, end_i: int) -> bool:
	var y: int = cells[start_i].y
	for i in range(start_i + 1, end_i + 1):
		if cells[i].y != y:
			return false
	return true


static func _has_line_of_sight(start_c: Vector3i, end_c: Vector3i, is_walkable: Callable) -> bool:
	if start_c.y != end_c.y:
		return false

	var p0 := Vector2(float(start_c.x) + 0.5, float(start_c.z) + 0.5)
	var p1 := Vector2(float(end_c.x) + 0.5, float(end_c.z) + 0.5)
	var dist := p0.distance_to(p1)
	if dist <= 0.001:
		return true

	# Step along the ray in increments of 0.35m (matching colonist capsule radius)
	var step_size := 0.35
	var steps := int(ceil(dist / step_size))
	var y_level := start_c.y

	for i in range(1, steps):
		var t := float(i) / float(steps)
		var p := p0.lerp(p1, t)
		var cx := int(floor(p.x))
		var cz := int(floor(p.y))
		var sample_cell := Vector3i(cx, y_level, cz)

		if not is_walkable.call(sample_cell):
			return false

	return true
