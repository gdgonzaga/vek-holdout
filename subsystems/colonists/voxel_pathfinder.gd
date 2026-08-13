extends Node
class_name VoxelPathfinder

## Voxel A* pathfinder with an injected walkability predicate (Phase 3).
##
## Intentionally generic: knows nothing about voxels/furniture/blueprints. A
## caller (MapWiring.wire_colonists) composes a per-cell is_walkable(Vector3i)
## Callable from VoxelGrid solidity + FurnitureLayer/BlueprintLayer occupancy
## and injects it via set_walkability(). find_path() runs A* over cells using
## that predicate for lazy neighbor expansion; output is world Vector3 waypoints
## sized for Colonist.set_path() (whose locomotion zeroes Y, so waypoint Y is
## informative, not load-bearing).
##
## Neighbor model (MVP): 4-connected horizontal on the standing Y — correct for
## flat terrain. Step-up/down + multi-level are deferred; the floor-based
## predicate validates every cell, so widening neighbors later is localized.

const _DOWN := Vector3i(0, -1, 0)
const _NEIGHBORS_4 := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const _MAX_EXPLORED := 4000   # backstop against runaway searches
const _STAND_SCAN := 3        # +/- Y cells scanned by find_stand_cell
const _CELL_HALF := Vector3(0.5, 0.5, 0.5)

var _is_walkable: Callable


## Inject the per-cell walkability predicate (composed by the wiring layer).
func set_walkability(predicate: Callable) -> void:
	_is_walkable = predicate


## Core A* over cells. Returns cell waypoints start->target (empty if no path,
## predicate unset, target not standable, or start==target). The predicate gates
## every expanded cell lazily.
func find_path(start_cell: Vector3i, target_cell: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	if not _is_walkable.is_valid():
		push_warning("VoxelPathfinder: walkability predicate not set")
		return path
	if start_cell == target_cell or not _is_walkable.call(target_cell):
		return path

	# Standard A* with Dictionary-backed open/closed sets (MVP search sizes
	# don't justify a heap; _MAX_EXPLORED bounds the work).
	var g_score: Dictionary = { start_cell: 0.0 }
	var came_from: Dictionary = {}
	var open: Array[Vector3i] = [start_cell]
	var closed: Dictionary = {}
	var explored := 0

	while not open.is_empty():
		# Pop the open cell with the lowest f = g + h (linear min-scan).
		var best_i := 0
		var best_f := INF
		for i in range(open.size()):
			var f: float = g_score[open[i]] + _heuristic(open[i], target_cell)
			if f < best_f:
				best_f = f
				best_i = i
		var current: Vector3i = open.pop_at(best_i)
		if current == target_cell:
			return _reconstruct(came_from, current)
		if closed.has(current):
			continue
		closed[current] = true
		explored += 1
		if explored > _MAX_EXPLORED:
			push_warning("VoxelPathfinder: exceeded %d cells, giving up" % _MAX_EXPLORED)
			return path
		for off in _NEIGHBORS_4:
			var nb: Vector3i = current + off
			if closed.has(nb) or not _is_walkable.call(nb):
				continue
			var tentative: float = g_score[current] + 1.0
			if tentative < g_score.get(nb, INF):
				g_score[nb] = tentative
				came_from[nb] = current
				if not open.has(nb):
					open.append(nb)
	return path


## Manhattan distance on the horizontal plane (Y is constant for 4-connected
## MVP moves). Admissible for unit step costs.
func _heuristic(a: Vector3i, b: Vector3i) -> float:
	return float(abs(a.x - b.x) + abs(a.z - b.z))


func _reconstruct(came_from: Dictionary, end: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [end]
	var current: Vector3i = end
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path


## Resolve a standable cell near a world position (scan down then up within
## +/-_STAND_SCAN). Handles the spawn-drop resting height + minor floor-height
## ambiguity. Falls back to the floored cell (find_path then fails clean) if
## none standable in the window or the predicate isn't set.
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
	return base


## Convert cell waypoints to world-space centers (XZ-centered; Y at cell center
## — ignored by Colonist locomotion, which navigates on the XZ plane).
func to_world_waypoints(cells: Array[Vector3i]) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for c in cells:
		pts.append(Vector3(c) + _CELL_HALF)
	return pts


## Convenience: world->stand-cell->A*->world. Resolves both ends via the
## vertical find_stand_cell scan — use only when the target is standable terrain,
## NOT a blocked footprint (use find_path_to_adjacent for that).
func find_path_world(start_world: Vector3, target_world: Vector3) -> Array[Vector3]:
	var cells := find_path(find_stand_cell(start_world), find_stand_cell(target_world))
	return to_world_waypoints(cells)


## Nearest walkable cell to `center` via a horizontal ring search on the same Y.
## Use when `center` may sit on a blocked footprint (a blueprint's footprint
## center): the colonist must stand ADJACENT to a build target, never on it, so
## the path target is the nearest free neighbour, not the center itself. Returns
## `center` unchanged if it is already walkable or if no walkable cell is found
## within max_radius (find_path then fails clean -> empty path). Rings expand
## outward, returning the nearest walkable cell of the first non-empty ring, so
## the result is the globally-nearest standable neighbour (same-Y, flat-terrain
## MVP assumption carried from the 4-connected neighbor model).
func find_stand_near_cell(center: Vector3i, max_radius: int = 4) -> Vector3i:
	if not _is_walkable.is_valid():
		return center
	if _is_walkable.call(center):
		return center
	for r in range(1, max_radius + 1):
		var best := center
		var best_d := INF
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if max(absi(dx), absi(dz)) != r:   # only the ring at Chebyshev distance r
					continue
				var c := center + Vector3i(dx, 0, dz)
				if _is_walkable.call(c):
					var d := float(dx * dx + dz * dz)
					if d < best_d:
						best_d = d
						best = c
		if best_d < INF:
			return best
	return center


## Like find_path_world, but resolves the TARGET via a horizontal ring search so
## the colonist can reach a point on a blocked footprint (a blueprint). The
## colonist ends up on the nearest stand-adjacent cell. Entry point for
## ColonistAI's build jobs (job.location is a blueprint footprint-center).
func find_path_to_adjacent(start_world: Vector3, target_world: Vector3, max_radius: int = 4) -> Array[Vector3]:
	var start_cell := find_stand_cell(start_world)
	var target_base := Vector3i(int(floor(target_world.x)), int(floor(target_world.y)), int(floor(target_world.z)))
	var target_cell := find_stand_near_cell(target_base, max_radius)
	return to_world_waypoints(find_path(start_cell, target_cell))
