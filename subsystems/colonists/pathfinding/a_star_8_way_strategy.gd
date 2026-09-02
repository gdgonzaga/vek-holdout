class_name AStar8WayStrategy
extends PathfindingStrategy

## 8-directional stepped voxel A* pathfinder.
##
## Expands 8 horizontal directions (4 cardinal + 4 diagonal) crossed with
## vertical dy in {+1, 0, -1..-max_drop}. Includes corner-cutting collision checks
## to prevent diagonal movement through solid wall corners.

const _SQRT2 := 1.41421356

const _NEIGHBORS_8 := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 1), Vector3i(1, 0, -1),
	Vector3i(-1, 0, 1), Vector3i(-1, 0, -1),
]


func get_strategy_name() -> String:
	return "AStar8Way"


func find_path(start_cell: Vector3i, target_cell: Vector3i, context: Dictionary) -> Dictionary:
	var is_walkable: Callable = context.get("is_walkable", Callable())
	var max_explored: int = context.get("max_explored", 8000)
	var max_drop: int = context.get("max_drop", 3)
	var jump_up_cost: float = context.get("jump_up_cost", 3.0)
	var drop_cost_per_cell: float = context.get("drop_cost_per_cell", 1.5)

	if not is_walkable.is_valid():
		return {"path": [] as Array[Vector3i], "explored": 0, "status": "FAIL (predicate not set)"}
	if not is_walkable.call(target_cell):
		return {"path": [] as Array[Vector3i], "explored": 0, "status": "FAIL (Target unwalkable %s)" % str(target_cell)}
	if start_cell == target_cell:
		return {"path": [start_cell] as Array[Vector3i], "explored": 0, "status": "OK (Already at target)"}

	var neighbors := _build_stepped_neighbors(max_drop)
	var g_score: Dictionary = {start_cell: 0.0}
	var came_from: Dictionary = {}
	var open: Array[Vector3i] = [start_cell]
	var closed: Dictionary = {}
	var explored := 0

	while not open.is_empty():
		var best_i := 0
		var best_f := INF
		for i in range(open.size()):
			var f: float = g_score[open[i]] + _heuristic_octile(open[i], target_cell)
			if f < best_f:
				best_f = f
				best_i = i
		var current: Vector3i = open.pop_at(best_i)
		if current == target_cell:
			var path := reconstruct_path(came_from, current)
			return {"path": path, "explored": explored, "status": "OK (%d pts, %d explored)" % [path.size(), explored]}
		if closed.has(current):
			continue
		closed[current] = true
		explored += 1
		if explored > max_explored:
			push_warning("AStar8WayStrategy: exceeded %d cells" % max_explored)
			return {"path": [] as Array[Vector3i], "explored": explored, "status": "FAIL (Exceeded max %d explored)" % max_explored}

		for off in neighbors:
			var nb: Vector3i = current + off
			if closed.has(nb) or not is_walkable.call(nb):
				continue
			if not _is_diagonal_passable(current, off, is_walkable):
				continue

			var tentative: float = g_score[current] + _move_cost(off, jump_up_cost, drop_cost_per_cell)
			if tentative < g_score.get(nb, INF):
				g_score[nb] = tentative
				came_from[nb] = current
				if not open.has(nb):
					open.append(nb)

	return {"path": [] as Array[Vector3i], "explored": explored, "status": "FAIL (No path, %d explored)" % explored}


func find_path_multi_target(start_cell: Vector3i, targets: Array[Vector3i], context: Dictionary) -> Dictionary:
	var is_walkable: Callable = context.get("is_walkable", Callable())
	var max_explored: int = context.get("max_explored", 8000)
	var max_drop: int = context.get("max_drop", 3)
	var jump_up_cost: float = context.get("jump_up_cost", 3.0)
	var drop_cost_per_cell: float = context.get("drop_cost_per_cell", 1.5)

	if targets.is_empty():
		return {"path": [] as Array[Vector3i], "target": Vector3i.MAX, "explored": 0, "status": "FAIL (No candidate targets)"}
	if not is_walkable.is_valid():
		return {"path": [] as Array[Vector3i], "target": targets[0], "explored": 0, "status": "FAIL (predicate not set)"}

	var target_set: Dictionary = {}
	for t in targets:
		target_set[t] = true

	if target_set.has(start_cell):
		return {"path": [start_cell] as Array[Vector3i], "target": start_cell, "explored": 0, "status": "OK (Already at target)"}

	var neighbors := _build_stepped_neighbors(max_drop)
	var g_score: Dictionary = {start_cell: 0.0}
	var came_from: Dictionary = {}
	var open: Array[Vector3i] = [start_cell]
	var closed: Dictionary = {}
	var explored := 0

	while not open.is_empty():
		var best_i := 0
		var best_f := INF
		for i in range(open.size()):
			var h := _heuristic_multi_octile(open[i], targets)
			var f: float = g_score[open[i]] + h
			if f < best_f:
				best_f = f
				best_i = i
		var current: Vector3i = open.pop_at(best_i)
		if target_set.has(current):
			var path := reconstruct_path(came_from, current)
			return {"path": path, "target": current, "explored": explored, "status": "OK (%d pts, %d explored)" % [path.size(), explored]}
		if closed.has(current):
			continue
		closed[current] = true
		explored += 1
		if explored > max_explored:
			push_warning("AStar8WayStrategy: exceeded %d cells" % max_explored)
			return {"path": [] as Array[Vector3i], "target": targets[0], "explored": explored, "status": "FAIL (Exceeded max %d explored)" % max_explored}

		for off in neighbors:
			var nb: Vector3i = current + off
			if closed.has(nb) or not is_walkable.call(nb):
				continue
			if not _is_diagonal_passable(current, off, is_walkable):
				continue

			var tentative: float = g_score[current] + _move_cost(off, jump_up_cost, drop_cost_per_cell)
			if tentative < g_score.get(nb, INF):
				g_score[nb] = tentative
				came_from[nb] = current
				if not open.has(nb):
					open.append(nb)

	return {"path": [] as Array[Vector3i], "target": targets[0], "explored": explored, "status": "FAIL (No path, %d explored)" % explored}


static func _is_diagonal_passable(current: Vector3i, off: Vector3i, is_walkable: Callable) -> bool:
	if off.x == 0 or off.z == 0:
		return true # Cardinal move, no corner to cut
	# For a diagonal move, check adjacent cardinal cells so we don't cut corners
	# through walls or impassable terrain.
	var adj_x := current + Vector3i(off.x, 0, 0)
	var adj_z := current + Vector3i(0, 0, off.z)
	var adj_x_at_target := current + Vector3i(off.x, off.y, 0)
	var adj_z_at_target := current + Vector3i(0, off.y, off.z)

	var side_x_ok: bool = bool(is_walkable.call(adj_x)) or (off.y != 0 and bool(is_walkable.call(adj_x_at_target)))
	var side_z_ok: bool = bool(is_walkable.call(adj_z)) or (off.y != 0 and bool(is_walkable.call(adj_z_at_target)))

	# Require both adjacent orthogonal sides to be passable to avoid clipping through wall corners
	return side_x_ok and side_z_ok


static func _build_stepped_neighbors(max_drop: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for dy in range(1, -max_drop - 1, -1):
		for h in _NEIGHBORS_8:
			result.append(Vector3i(h.x, dy, h.z))
	return result


static func _move_cost(off: Vector3i, jump_up_cost: float, drop_cost_per_cell: float) -> float:
	var is_diag := (off.x != 0 and off.z != 0)
	var base_cost := _SQRT2 if is_diag else 1.0
	if off.y > 0:
		return jump_up_cost * base_cost
	if off.y < 0:
		return (drop_cost_per_cell * float(-off.y)) + (base_cost - 1.0)
	return base_cost


static func _heuristic_octile(a: Vector3i, b: Vector3i) -> float:
	var dx := float(abs(a.x - b.x))
	var dz := float(abs(a.z - b.z))
	var d_min := minf(dx, dz)
	var d_max := maxf(dx, dz)
	return (d_max - d_min) + d_min * _SQRT2


static func _heuristic_multi_octile(a: Vector3i, targets: Array[Vector3i]) -> float:
	var best := INF
	for t in targets:
		var d := _heuristic_octile(a, t)
		if d < best:
			best = d
	return best
