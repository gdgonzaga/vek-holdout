class_name ThetaStarStrategy
extends PathfindingStrategy

## Any-Angle Theta* voxel pathfinder.
##
## Extends A* by checking line-of-sight between a candidate neighbor and the current
## node's parent (grandparent shortcutting). Produces direct any-angle paths during
## search rather than restricting parent links to immediate grid neighbors.

const _SQRT2 := 1.41421356

const _NEIGHBORS_8 := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 1), Vector3i(1, 0, -1),
	Vector3i(-1, 0, 1), Vector3i(-1, 0, -1),
]


func get_strategy_name() -> String:
	return "ThetaStar"


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
			var f: float = g_score[open[i]] + _heuristic_euclidean(open[i], target_cell)
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
			push_warning("ThetaStarStrategy: exceeded %d cells" % max_explored)
			return {"path": [] as Array[Vector3i], "explored": explored, "status": "FAIL (Exceeded max %d explored)" % max_explored}

		for off in neighbors:
			var nb: Vector3i = current + off
			if closed.has(nb) or not is_walkable.call(nb):
				continue

			var parent: Vector3i = current
			var tentative_g: float = 0.0

			# Theta* condition: Check line of sight from grandparent
			if came_from.has(current) and _has_line_of_sight(came_from[current], nb, is_walkable):
				var grandparent: Vector3i = came_from[current]
				parent = grandparent
				tentative_g = g_score[grandparent] + _euclidean_cost(grandparent, nb, jump_up_cost, drop_cost_per_cell)
			else:
				tentative_g = g_score[current] + _move_cost(off, jump_up_cost, drop_cost_per_cell)

			if tentative_g < g_score.get(nb, INF):
				g_score[nb] = tentative_g
				came_from[nb] = parent
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
			var h := _heuristic_multi_euclidean(open[i], targets)
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
			push_warning("ThetaStarStrategy: exceeded %d cells" % max_explored)
			return {"path": [] as Array[Vector3i], "target": targets[0], "explored": explored, "status": "FAIL (Exceeded max %d explored)" % max_explored}

		for off in neighbors:
			var nb: Vector3i = current + off
			if closed.has(nb) or not is_walkable.call(nb):
				continue

			var parent: Vector3i = current
			var tentative_g: float = 0.0

			if came_from.has(current) and _has_line_of_sight(came_from[current], nb, is_walkable):
				var grandparent: Vector3i = came_from[current]
				parent = grandparent
				tentative_g = g_score[grandparent] + _euclidean_cost(grandparent, nb, jump_up_cost, drop_cost_per_cell)
			else:
				tentative_g = g_score[current] + _move_cost(off, jump_up_cost, drop_cost_per_cell)

			if tentative_g < g_score.get(nb, INF):
				g_score[nb] = tentative_g
				came_from[nb] = parent
				if not open.has(nb):
					open.append(nb)

	return {"path": [] as Array[Vector3i], "target": targets[0], "explored": explored, "status": "FAIL (No path, %d explored)" % explored}


static func _has_line_of_sight(start_c: Vector3i, end_c: Vector3i, is_walkable: Callable) -> bool:
	if start_c.y != end_c.y:
		return false

	var p0 := Vector2(float(start_c.x) + 0.5, float(start_c.z) + 0.5)
	var p1 := Vector2(float(end_c.x) + 0.5, float(end_c.z) + 0.5)
	var dist := p0.distance_to(p1)
	if dist <= 0.001:
		return true

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


static func _euclidean_cost(a: Vector3i, b: Vector3i, jump_up_cost: float, drop_cost_per_cell: float) -> float:
	var p0 := Vector2(float(a.x), float(a.z))
	var p1 := Vector2(float(b.x), float(b.z))
	var base := p0.distance_to(p1)
	var dy := b.y - a.y
	if dy > 0:
		return base + (jump_up_cost - 1.0) * float(dy)
	if dy < 0:
		return base + (drop_cost_per_cell - 1.0) * float(-dy)
	return base


static func _heuristic_euclidean(a: Vector3i, b: Vector3i) -> float:
	var p0 := Vector2(float(a.x), float(a.z))
	var p1 := Vector2(float(b.x), float(b.z))
	return p0.distance_to(p1)


static func _heuristic_multi_euclidean(a: Vector3i, targets: Array[Vector3i]) -> float:
	var best := INF
	var p0 := Vector2(float(a.x), float(a.z))
	for t in targets:
		var p1 := Vector2(float(t.x), float(t.z))
		var d := p0.distance_to(p1)
		if d < best:
			best = d
	return best
