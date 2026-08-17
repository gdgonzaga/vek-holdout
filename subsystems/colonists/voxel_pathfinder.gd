extends Node
class_name VoxelPathfinder

## Voxel A* pathfinder with an injected walkability predicate (Phase 3).
##
## Intentionally generic: knows nothing about voxels/furniture/blueprints. A
## caller (MapWiring.wire_colonists) composes a per-cell is_walkable(Vector3i)
## Callable from BlockyGrid solidity + FurnitureLayer/BlueprintLayer occupancy
## and injects it via set_walkability(). find_path() runs A* over cells using
## that predicate for lazy neighbor expansion; output is world Vector3 waypoints
## sized for Colonist.set_path() (whose locomotion zeroes Y, so waypoint Y is
## informative, not load-bearing).
##
## Neighbor model: stepped — the 4 horizontal directions crossed with dy in
## {+1, 0, -1..-_MAX_DROP}. +1 climbs one full block (the Colonist's
## StepClimber component hops the face at the obstacle — colonists have no
## manual jump); drops up to _MAX_DROP cells are walk-off-and-fall. Vertical
## moves cost extra so flat detours (and future stair blocks, once a per-block
## cost hook exists) win over jumping whenever comparable. Multi-cell drops
## assume an unobstructed fall column (the predicate only validates the landing
## cell); floating geometry in between can interrupt the fall — no recovery
## exists for interrupted MOVE legs either way.

const _DOWN := Vector3i(0, -1, 0)
## Horizontal-only adjacency: used where "stand adjacent to a footprint" is
## the question — ring/footprint expansion never changes Y.
const _NEIGHBORS_4 := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
## A* expansion offsets: 4 horizontal dirs x dy in {+1, 0, -1..-_MAX_DROP},
## written literally because const initializers can't call functions.
const _NEIGHBORS_STEPPED := [
	Vector3i(1, 1, 0), Vector3i(-1, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 1, -1),
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, -1, 0), Vector3i(-1, -1, 0), Vector3i(0, -1, 1), Vector3i(0, -1, -1),
	Vector3i(1, -2, 0), Vector3i(-1, -2, 0), Vector3i(0, -2, 1), Vector3i(0, -2, -1),
	Vector3i(1, -3, 0), Vector3i(-1, -3, 0), Vector3i(0, -3, 1), Vector3i(0, -3, -1),
]
## Maximum fall (in cells) a path may route over.
const _MAX_DROP := 3
## Climbing costs 3x a flat step so colonists prefer flat detours / stairs.
const _JUMP_UP_COST := 3.0
## Falling costs 1.5 per cell — cheaper than climbing, pricier than flat.
const _DROP_COST_PER_CELL := 1.5
const _MAX_EXPLORED := 8000 # backstop against runaway searches (20 neighbors/expand)
const _STAND_SCAN := 3 # +/- Y cells scanned by find_stand_cell
const _CELL_HALF := Vector3(0.5, 0.5, 0.5)

var _is_walkable: Callable

## Optional column stand-cell hint source, `(x: float, z: float) -> Vector3i`
## (composed by the wiring layer from the smooth heightfield, D4). Lets the
## stand-cell resolvers derive a column's true stand Y instead of assuming flat
## ground. Vector3i.MAX from the hint = "no answer for this column" -> the
## flat same-Y assumption applies, so hint-less maps behave exactly as before.
var _stand_cell_hint: Callable


## Inject the per-cell walkability predicate (composed by the wiring layer).
func set_walkability(predicate: Callable) -> void:
	_is_walkable = predicate


## Inject the column stand-cell hint source (MapWiring.smooth_stand_hint).
## Optional; without it the finder keeps its flat-terrain assumptions.
func set_stand_cell_hint(hint: Callable) -> void:
	_stand_cell_hint = hint


## Core A* over cells. Returns cell waypoints start->target (empty if no path,
## predicate unset, or target not standable). Returns [start_cell] when start
## already equals target. The predicate gates every expanded cell lazily.
func find_path(start_cell: Vector3i, target_cell: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	if not _is_walkable.is_valid():
		push_warning("VoxelPathfinder: walkability predicate not set")
		return path
	if not _is_walkable.call(target_cell):
		return path
	if start_cell == target_cell:
		return [start_cell]

	# Standard A* with Dictionary-backed open/closed sets (MVP search sizes
	# don't justify a heap; _MAX_EXPLORED bounds the work).
	var g_score: Dictionary = {start_cell: 0.0}
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
		for off in _NEIGHBORS_STEPPED:
			var nb: Vector3i = current + off
			if closed.has(nb) or not _is_walkable.call(nb):
				continue
			var tentative: float = g_score[current] + _move_cost(off)
			if tentative < g_score.get(nb, INF):
				g_score[nb] = tentative
				came_from[nb] = current
				if not open.has(nb):
					open.append(nb)
	return path


## Traversal cost of one stepped move: flat 1.0, climb _JUMP_UP_COST, drop
## _DROP_COST_PER_CELL per cell fallen.
func _move_cost(off: Vector3i) -> float:
	if off.y > 0:
		return _JUMP_UP_COST
	if off.y < 0:
		return _DROP_COST_PER_CELL * float(-off.y)
	return 1.0


## Manhattan distance on the horizontal plane. Vertical moves are ignored by
## the heuristic but cost >= 1.0 each, so it stays admissible (never
## overestimates) for the stepped neighbor model.
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
## +/-_STAND_SCAN, then the column hint). Handles the spawn-drop resting
## height + minor floor-height ambiguity; the hint covers terrain whose stand
## Y is farther than the scan window from the query Y (a plate-height job
## location on a tall hill column). Falls back to the floored cell
## (find_path then fails clean) if nothing standable resolves.
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
	return base


## Stand-cell candidate for the column of `pos`: the hint's derived stand cell
## when a hint source is injected and answers for this column, else `pos`
## itself (the flat-terrain same-Y assumption — also the no-hint behavior).
func _column_stand_cell(pos: Vector3i) -> Vector3i:
	if _stand_cell_hint.is_valid():
		var hinted: Vector3i = _stand_cell_hint.call(float(pos.x), float(pos.z))
		if hinted != Vector3i.MAX:
			return hinted
	return pos


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


## Nearest walkable cell to `center` via a horizontal ring search. Use when
## `center` may sit on a blocked footprint (a blueprint's footprint
## center): the colonist must stand ADJACENT to a build target, never on it, so
## the path target is the nearest free neighbour, not the center itself. Returns
## `center` unchanged if it is already walkable or if no walkable cell is found
## within max_radius (find_path then fails clean -> empty path). Rings expand
## outward, returning the nearest walkable cell of the first non-empty ring, so
## the result is the globally-nearest standable neighbour. Each ring position
## resolves its column's stand cell via the hint when one is injected (smooth
## hills stand +/-1 Y per step, D4) and stays same-Y otherwise — the original
## flat-terrain assumption, now only the fallback.
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
				if max(absi(dx), absi(dz)) != r: # only the ring at Chebyshev distance r
					continue
				var c := _column_stand_cell(center + Vector3i(dx, 0, dz))
				if not _is_walkable.call(c):
					continue
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


## Path from start_world to the walkable cell adjacent to any cell in
## `footprint` that is closest to the colonist (multi-target A*). Use this
## instead of find_path_to_adjacent when the target is a furniture node whose
## full footprint is known — handles irregularly-shaped / multi-cell pieces
## correctly regardless of which side the colonist approaches from.
func find_path_to_footprint_adjacent(start_world: Vector3, footprint: Array[Vector3i]) -> Array[Vector3]:
	var start_cell := find_stand_cell(start_world)
	# Expand footprint to all immediately-adjacent walkable cells.
	var fp_set: Dictionary = {}
	for c in footprint:
		fp_set[c] = true
	var candidates: Array[Vector3i] = []
	for c in footprint:
		for off in _NEIGHBORS_4:
			var nb: Vector3i = c + off
			if fp_set.has(nb):
				continue # inside the footprint itself
			if not _is_walkable.call(nb):
				continue
			if not candidates.has(nb):
				candidates.append(nb)
	if candidates.is_empty():
		return []
	return to_world_waypoints(_find_path_multi_target(start_cell, candidates))


## A* from `start` to the nearest cell in `targets` (the goal set).
## Heuristic: min Manhattan distance to any target (still admissible).
func _find_path_multi_target(start: Vector3i, targets: Array[Vector3i]) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	if targets.is_empty() or not _is_walkable.is_valid():
		return path
	var target_set: Dictionary = {}
	for t in targets:
		target_set[t] = true
	var g_score: Dictionary = {start: 0.0}
	var came_from: Dictionary = {}
	var open: Array[Vector3i] = [start]
	var closed: Dictionary = {}
	var explored := 0
	while not open.is_empty():
		var best_i := 0
		var best_f := INF
		for i in range(open.size()):
			var h := _heuristic_multi(open[i], targets)
			var f: float = g_score[open[i]] + h
			if f < best_f:
				best_f = f
				best_i = i
		var current: Vector3i = open.pop_at(best_i)
		if target_set.has(current):
			return _reconstruct(came_from, current)
		if closed.has(current):
			continue
		closed[current] = true
		explored += 1
		if explored > _MAX_EXPLORED:
			push_warning("VoxelPathfinder: exceeded %d cells" % _MAX_EXPLORED)
			return path
		for off in _NEIGHBORS_STEPPED:
			var nb: Vector3i = current + off
			if closed.has(nb) or not _is_walkable.call(nb):
				continue
			var tentative: float = g_score[current] + _move_cost(off)
			if tentative < g_score.get(nb, INF):
				g_score[nb] = tentative
				came_from[nb] = current
				if not open.has(nb):
					open.append(nb)
	return path
func _heuristic_multi(a: Vector3i, targets: Array[Vector3i]) -> float:
	var best := INF
	for t in targets:
		var d := float(abs(a.x - t.x) + abs(a.z - t.z))
		if d < best:
			best = d
	return best
