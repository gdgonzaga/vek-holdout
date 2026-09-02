extends Node
class_name VoxelPathfinder

## Voxel pathfinder supporting pluggable pathfinding and smoothing strategies (Phase 3).
##
## Generic and decoupled from world storage: callers inject a per-cell
## `is_walkable(Vector3i)` Callable (and optional column stand hint) via
## `set_walkability()` / `set_stand_cell_hint()`.
##
## Uses a pluggable PathfindingStrategy (default: SmoothedAStarStrategy / GameState configured)
## for A*, 8-way, and line-of-sight shortcutting, producing natural direct paths
## across open flat ground while strictly adhering to voxel climb (+1), drop (-1..-3),
## and clearance invariants.

const _SmoothedAStarScript = preload("res://subsystems/colonists/pathfinding/smoothed_a_star_strategy.gd")

const _DOWN := Vector3i(0, -1, 0)
const _NEIGHBORS_4 := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const _MAX_DROP := 3
const _JUMP_UP_COST := 3.0
const _DROP_COST_PER_CELL := 1.5
const _MAX_EXPLORED := 8000
const _STAND_SCAN := 3
const _CELL_HALF := Vector3(0.5, 0.5, 0.5)

var _is_walkable: Callable
var _stand_cell_hint: Callable

## Active pathfinding and smoothing strategy.
var strategy: PathfindingStrategy

# Telemetry / Diagnostics
var last_query_start: Vector3i = Vector3i.MAX
var last_stand_candidates: Array[Dictionary] = []
var last_query_target: Vector3i = Vector3i.MAX
var last_status: String = "IDLE"
var last_explored_count: int = 0
var last_query_time: float = -1.0


func _init(initial_strategy: PathfindingStrategy = null) -> void:
	if initial_strategy != null:
		strategy = initial_strategy
	else:
		strategy = _SmoothedAStarScript.new()


func _ready() -> void:
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state != null and game_state.has_method("create_pathfinding_strategy"):
		strategy = game_state.create_pathfinding_strategy()


## Set or switch the active pathfinding strategy at runtime.
func set_strategy(new_strategy: PathfindingStrategy) -> void:
	if new_strategy != null:
		strategy = new_strategy


## Inject the per-cell walkability predicate (composed by the wiring layer).
func set_walkability(predicate: Callable) -> void:
	_is_walkable = predicate


## Inject the column stand-cell hint source (MapWiring.smooth_stand_hint).
## Optional; without it the finder keeps its flat-terrain assumptions.
func set_stand_cell_hint(hint: Callable) -> void:
	_stand_cell_hint = hint


## Query whether a given voxel cell is standable under the injected predicate.
func is_walkable(cell: Vector3i) -> bool:
	return _is_walkable.is_valid() and bool(_is_walkable.call(cell))


## Refresh the telemetry clock. Called by every query that writes last_* fields.
func _stamp_query_time() -> void:
	last_query_time = float(Time.get_ticks_msec()) * 0.001


func _build_context() -> Dictionary:
	return {
		"is_walkable": _is_walkable,
		"stand_cell_hint": _stand_cell_hint,
		"max_drop": _MAX_DROP,
		"jump_up_cost": _JUMP_UP_COST,
		"drop_cost_per_cell": _DROP_COST_PER_CELL,
		"max_explored": _MAX_EXPLORED,
	}


## Core path search over cells using the active strategy.
func find_path(start_cell: Vector3i, target_cell: Vector3i) -> Array[Vector3i]:
	_stamp_query_time()
	last_query_start = start_cell
	last_query_target = target_cell
	last_explored_count = 0

	if not _is_walkable.is_valid():
		push_warning("VoxelPathfinder: walkability predicate not set")
		last_status = "FAIL (predicate not set)"
		return []

	if strategy == null:
		strategy = _SmoothedAStarScript.new()

	var result: Dictionary = strategy.find_path(start_cell, target_cell, _build_context())
	last_explored_count = int(result.get("explored", 0))
	last_status = str(result.get("status", "IDLE"))
	var path: Array[Vector3i] = result.get("path", [] as Array[Vector3i])
	return path


## Multi-target A* using the active strategy.
func _find_path_multi_target(start: Vector3i, targets: Array[Vector3i]) -> Array[Vector3i]:
	_stamp_query_time()
	last_query_start = start
	if not targets.is_empty():
		last_query_target = targets[0]
	last_explored_count = 0

	if targets.is_empty():
		last_status = "FAIL (No candidate targets)"
		return []
	if not _is_walkable.is_valid():
		last_status = "FAIL (predicate not set)"
		return []

	if strategy == null:
		strategy = _SmoothedAStarScript.new()

	var result: Dictionary = strategy.find_path_multi_target(start, targets, _build_context())
	last_explored_count = int(result.get("explored", 0))
	last_status = str(result.get("status", "IDLE"))
	if result.has("target") and result.target != Vector3i.MAX:
		last_query_target = result.target
	var path: Array[Vector3i] = result.get("path", [] as Array[Vector3i])
	return path


## Convert cell waypoints to world-space coordinates via the active strategy.
func to_world_waypoints(cells: Array[Vector3i]) -> Array[Vector3]:
	if strategy == null:
		strategy = _SmoothedAStarScript.new()
	return strategy.to_world_waypoints(cells, _build_context())


## Convenience: world->stand-cell->A*->world. Resolves both ends via the
## vertical find_stand_cell scan — use only when the target is standable terrain,
## NOT a blocked footprint (use find_path_to_adjacent for that).
func find_path_world(start_world: Vector3, target_world: Vector3) -> Array[Vector3]:
	var cells := find_path(find_stand_cell(start_world), find_stand_cell(target_world))
	return to_world_waypoints(cells)


## Nearest walkable cell to `center` via a horizontal ring search.
func find_stand_near_cell(center: Vector3i, max_radius: int = 4) -> Vector3i:
	_stamp_query_time()
	last_stand_candidates.clear()
	if not _is_walkable.is_valid():
		return center
	if _is_walkable.call(center):
		last_stand_candidates.append({"cell": center, "walkable": true, "chosen": true})
		return center
	for r in range(1, max_radius + 1):
		var best := center
		var best_d := INF
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if max(absi(dx), absi(dz)) != r:
					continue
				var col_base := center + Vector3i(dx, 0, dz)
				var c := _stand_cell_in_column(col_base, r + 1)
				if c == Vector3i.MAX:
					last_stand_candidates.append({"cell": col_base, "walkable": false, "chosen": false})
					continue
				
				var d := float(dx * dx + dz * dz + (c.y - center.y) * (c.y - center.y))
				last_stand_candidates.append({"cell": c, "walkable": true, "chosen": false, "dist": d})
				if d < best_d:
					best_d = d
					best = c
		if best_d < INF:
			for cand in last_stand_candidates:
				if cand.cell == best:
					cand.chosen = true
			return best
	return center


## Like find_path_world, but resolves the TARGET via a horizontal ring search so
## the colonist can reach a point on a blocked footprint (a blueprint).
func find_path_to_adjacent(start_world: Vector3, target_world: Vector3, max_radius: int = 4) -> Array[Vector3]:
	var start_cell := find_stand_cell(start_world)
	var target_base := Vector3i(int(floor(target_world.x)), int(floor(target_world.y)), int(floor(target_world.z)))
	var target_cell := find_stand_near_cell(target_base, max_radius)
	return to_world_waypoints(find_path(start_cell, target_cell))


## Path from start_world to the walkable cell adjacent to any cell in
## `footprint` that is closest to the colonist (multi-target A*).
func find_path_to_footprint_adjacent(start_world: Vector3, footprint: Array[Vector3i]) -> Array[Vector3]:
	_stamp_query_time()
	var start_cell := find_stand_cell(start_world)
	var fp_set: Dictionary = {}
	for c in footprint:
		fp_set[c] = true
	var candidates: Array[Vector3i] = []
	for c in footprint:
		for off in _NEIGHBORS_4:
			var col: Vector3i = c + off
			if fp_set.has(col):
				continue
			var stand := _stand_cell_in_column(col, 2)
			if stand == Vector3i.MAX or fp_set.has(stand):
				continue
			if not candidates.has(stand):
				candidates.append(stand)
	if candidates.is_empty():
		last_query_start = start_cell
		last_status = "FAIL (No walkable adjacent cells to footprint)"
		return []
	return to_world_waypoints(_find_path_multi_target(start_cell, candidates))


## Resolve a standable cell near a world position (scan down then up within
## +/-_STAND_SCAN, then the column hint).
func find_stand_cell(world_pos: Vector3) -> Vector3i:
	var base := Vector3i(int(floor(world_pos.x)), int(floor(world_pos.y)), int(floor(world_pos.z)))
	if not _is_walkable.is_valid():
		return base
	for dy in range(0, -_STAND_SCAN - 1, -1):
		var c := base + Vector3i(0, dy, 0)
		if _is_walkable.call(c):
			return c
	for dy in range(1, _STAND_SCAN + 1):
		var c := base + Vector3i(0, dy, 0)
		if _is_walkable.call(c):
			return c
	var hinted := _column_stand_cell(base)
	if hinted != base and _is_walkable.call(hinted):
		return hinted
	var near_cell := find_stand_near_cell(base, _STAND_SCAN)
	if _is_walkable.call(near_cell):
		return near_cell
	return base


func _column_stand_cell(pos: Vector3i) -> Vector3i:
	if _stand_cell_hint.is_valid():
		var hinted: Variant = _stand_cell_hint.call(float(pos.x) + 0.5, float(pos.z) + 0.5)
		if hinted is Vector3i and hinted != Vector3i.MAX:
			return hinted
	return pos


func _stand_cell_in_column(col_base: Vector3i, max_hint_dy: int = 1) -> Vector3i:
	if _is_walkable.call(col_base):
		return col_base
	if _is_walkable.call(col_base + Vector3i.UP):
		return col_base + Vector3i.UP
	if _is_walkable.call(col_base + Vector3i.DOWN):
		return col_base + Vector3i.DOWN
	var hinted := _column_stand_cell(col_base)
	if hinted != col_base and absi(hinted.y - col_base.y) <= max_hint_dy and _is_walkable.call(hinted):
		return hinted
	return Vector3i.MAX


func clear_diagnostics() -> void:
	last_query_start = Vector3i.MAX
	last_query_target = Vector3i.MAX
	last_stand_candidates.clear()
	last_status = "IDLE"
	last_query_time = -1.0
