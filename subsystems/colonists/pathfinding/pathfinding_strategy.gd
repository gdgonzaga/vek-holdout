class_name PathfindingStrategy
extends RefCounted

## Abstract base strategy for voxel pathfinding and path post-processing.
##
## Defines the contract for path search solvers and waypoint smoothers.
## Implementations receive a standardized `context` Dictionary containing:
## - "is_walkable": Callable (Vector3i -> bool)
## - "stand_cell_hint": Callable (float, float -> Vector3i) [optional]
## - "max_drop": int (e.g. 3)
## - "jump_up_cost": float (e.g. 3.0)
## - "drop_cost_per_cell": float (e.g. 1.5)
## - "max_explored": int (e.g. 8000)

const CELL_HALF := Vector3(0.5, 0.5, 0.5)


## Search for a path from start_cell to target_cell.
## Returns a Dictionary with:
## - "path": Array[Vector3i]
## - "explored": int
## - "status": String
func find_path(_start_cell: Vector3i, _target_cell: Vector3i, _context: Dictionary) -> Dictionary:
	return {
		"path": [] as Array[Vector3i],
		"explored": 0,
		"status": "FAIL (not implemented)",
	}


## Multi-target search for the closest reachable goal in `targets`.
## Returns a Dictionary with:
## - "path": Array[Vector3i]
## - "target": Vector3i
## - "explored": int
## - "status": String
func find_path_multi_target(_start_cell: Vector3i, _targets: Array[Vector3i], _context: Dictionary) -> Dictionary:
	return {
		"path": [] as Array[Vector3i],
		"target": Vector3i.MAX,
		"explored": 0,
		"status": "FAIL (not implemented)",
	}


## Convert cell waypoints into world-space coordinates, with optional path
## smoothing or string pulling applied.
func to_world_waypoints(cells: Array[Vector3i], _context: Dictionary) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for c in cells:
		pts.append(Vector3(c) + CELL_HALF)
	return pts


## Human-readable name of the strategy for telemetry and diagnostics.
func get_strategy_name() -> String:
	return "BaseStrategy"


## Helper to reconstruct cell path from A* came_from map.
static func reconstruct_path(came_from: Dictionary, end_cell: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [end_cell]
	var current: Vector3i = end_cell
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path
