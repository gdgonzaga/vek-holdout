extends GdUnitTestSuite

## D4 invariant regression suite (dual-voxel Phase 3): the hybrid ground probe
## and the pathfinder's hinted stand-cell resolvers, over the same Dictionary
## mini-grid idiom as suite_voxel_pathfinder_test.gd. Smooth terrain is faked
## as a heightfield store (Vector2i column -> {h, n}) standing in for
## SmoothGrid.height_at — the real grid's ray/cache behavior is covered by
## suite_smooth_grid_test.gd; these tests pin the DECISIONS:
##   Invariant 1 (no regression): smooth-less maps answer identically.
##   Invariant 2 (edits keep pathing honest): carve / ramp / wall-off change
##   the next pathfind.

const _DOWN := Vector3i(0, -1, 0)
const _UP := Vector3i(0, 1, 0)
const _MAX_SLOPE_DEG := 45.0


# --- fakes ------------------------------------------------------------------

## Blocky stand-in: solid Dictionary -> get_block_at Callable.
func _fake_get_block_at(solid: Dictionary) -> Callable:
	return func(cell: Vector3i) -> String:
		return "stone" if solid.has(cell) else ""


## Smooth stand-in: heights Dictionary (Vector2i -> {"h": float, "n": Vector3})
## -> height_at Callable. Missing column = NAN, matching SmoothGrid where the
## terrain doesn't reach (or was carved away).
func _fake_height_at(heights: Dictionary) -> Callable:
	return func(x: float, z: float, normals: Array) -> float:
		var col := Vector2i(int(floor(x)), int(floor(z)))
		if not heights.has(col):
			return NAN
		var entry: Dictionary = heights[col]
		normals.append(entry["n"])
		return entry["h"]


## Column stand-cell hint over the same store, mirroring
## MapWiring.smooth_stand_hint's derivation (stand Y = floor(h)).
func _fake_hint(heights: Dictionary) -> Callable:
	return func(x: float, z: float) -> Vector3i:
		var col := Vector2i(int(floor(x)), int(floor(z)))
		if not heights.has(col):
			return Vector3i.MAX
		return Vector3i(col.x, int(floor(float(heights[col]["h"]))), col.y)


func _hybrid(solid: Dictionary, heights: Dictionary) -> Callable:
	return MapWiring.hybrid_ground_probe(_fake_get_block_at(solid), _fake_height_at(heights), _MAX_SLOPE_DEG)


func _flat_heights(x_min: int, x_max: int, z_min: int, z_max: int, h: float) -> Dictionary:
	var heights := {}
	for x in range(x_min, x_max + 1):
		for z in range(z_min, z_max + 1):
			heights[Vector2i(x, z)] = {"h": h, "n": Vector3.UP}
	return heights


func _fill_floor(solid: Dictionary, x_min: int, x_max: int, z_min: int, z_max: int, y: int) -> void:
	for x in range(x_min, x_max + 1):
		for z in range(z_min, z_max + 1):
			solid[Vector3i(x, y, z)] = true


# --- Invariant 1: no regression on smooth-less maps ---------------------------

## Where the smooth source answers NAN everywhere, the hybrid probe must answer
## identically to the plain blocky probe over a window spanning floors, blocks,
## and head-clearance cases.
func test_parity_no_smooth_matches_blocky_probe() -> void:
	var solid := {}
	_fill_floor(solid, -2, 2, -2, 2, 0)
	_fill_floor(solid, -2, 2, -2, 2, 3)  # ceiling band: head clearance cases
	solid[Vector3i(0, 1, 0)] = true      # free-standing block
	var blocky := MapWiring.blocky_ground_probe(_fake_get_block_at(solid))
	var hybrid := _hybrid(solid, {})
	var mismatches := 0
	for x in range(-2, 3):
		for y in range(-1, 5):
			for z in range(-2, 3):
				if blocky.call(Vector3i(x, y, z)) != hybrid.call(Vector3i(x, y, z)):
					mismatches += 1
	assert_int(mismatches).is_equal(0)


# --- hybrid probe: smooth stands, slope gate, burial --------------------------

## A smooth surface at 6.4 makes floor(6.4) = 6 the stand cell: cell 6 stands
## on it, cells below are buried, cells above have no blocky floor.
func test_smooth_surface_adds_stand_cells() -> void:
	var heights := _flat_heights(-3, 3, -3, 3, 6.4)
	var probe := _hybrid({}, heights)
	assert_bool(probe.call(Vector3i(0, 6, 0))).is_true()
	assert_bool(probe.call(Vector3i(2, 6, -1))).is_true()
	assert_bool(probe.call(Vector3i(0, 5, 0))).is_false()  # buried
	assert_bool(probe.call(Vector3i(0, 7, 0))).is_false()  # in air, no blocky floor


## Head clearance applies to smooth stands too: a blocky voxel in the cell
## above the stand cell blocks the 2-cell capsule.
func test_smooth_stand_needs_head_clearance() -> void:
	var heights := _flat_heights(-1, 1, -1, 1, 6.4)
	var solid := {Vector3i(0, 7, 0): true}
	var probe := _hybrid(solid, heights)
	assert_bool(probe.call(Vector3i(0, 6, 0))).is_false()
	assert_bool(probe.call(Vector3i(1, 6, 0))).is_true()


## D4 slope gate at 45deg: n.y = 0.5 (60deg slope) is unwalkable, n.y = 0.71
## stays walkable.
func test_slope_gate_blocks_steep_surfaces() -> void:
	var heights := {
		Vector2i(0, 0): {"h": 6.4, "n": Vector3(0.866, 0.5, 0.0)},
		Vector2i(1, 0): {"h": 6.4, "n": Vector3(0.704, 0.71, 0.0)},
	}
	var probe := _hybrid({}, heights)
	assert_bool(probe.call(Vector3i(0, 6, 0))).is_false()
	assert_bool(probe.call(Vector3i(1, 6, 0))).is_true()


## Where hills overlap the blocky plate, the plate-top column still reads
## air-above-solid to the blocky rules — but the burial rule must cancel it,
## while structures standing clear of the surface keep their blocky outcome.
func test_buried_plate_cells_cancel_but_clear_structures_survive() -> void:
	var heights := _flat_heights(-1, 1, -1, 1, 6.0)
	# Blocky plate: solid at y=0, so (x,1,z) is standable to the blocky rules.
	var solid := {}
	_fill_floor(solid, -1, 1, -1, 1, 0)
	# ...and a built platform at y=5 clear above the surface, standable at y=6.
	_fill_floor(solid, -1, 1, -1, 1, 5)
	var probe := _hybrid(solid, heights)
	assert_bool(probe.call(Vector3i(0, 1, 0))).is_false()  # buried plate cell
	assert_bool(probe.call(Vector3i(0, 6, 0))).is_true()   # clear structure cell
	assert_bool(probe.call(Vector3i(0, 6, 1))).is_true()   # also the hill top


# --- Invariant 2: edits keep pathing honest -----------------------------------

## Dig a trench (carve the smooth column away) across the only corridor: the
## crossing path that existed before must fail now, and backfill restores it.
func test_carve_trench_breaks_and_backfill_restores_path() -> void:
	var heights := _flat_heights(-2, 2, 0, 0, 1.4)
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(_hybrid({}, heights))
	assert_int(finder.find_path(Vector3i(-2, 1, 0), Vector3i(2, 1, 0)).size()).is_greater(0)
	# Carve: the middle column's ground is gone (heights store = the world the
	# probe reads; SmoothGrid evicts its cache on carve, so this models 1:1).
	heights.erase(Vector2i(0, 0))
	assert_int(finder.find_path(Vector3i(-2, 1, 0), Vector3i(2, 1, 0)).size()).is_equal(0)
	# Backfill (smooth placement): ground returns, so does the path.
	heights[Vector2i(0, 0)] = {"h": 1.4, "n": Vector3.UP}
	assert_int(finder.find_path(Vector3i(-2, 1, 0), Vector3i(2, 1, 0)).size()).is_greater(0)


## A walkable smooth ramp climbs one cell per column — the step model handles
## it with no hop tuning changes.
func test_smooth_ramp_path_climbs() -> void:
	var heights := {}
	var ramp := [0.5, 1.25, 2.0, 2.75]
	for x in range(ramp.size()):
		heights[Vector2i(x, 0)] = {"h": float(ramp[x]), "n": Vector3(0.6, 0.8, 0.0)}
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(_hybrid({}, heights))
	var path := finder.find_path(Vector3i(0, 0, 0), Vector3i(3, 2, 0))
	assert_int(path.size()).is_equal(4)
	assert_bool(path.has(Vector3i(1, 1, 0))).is_true()
	assert_bool(path.has(Vector3i(2, 2, 0))).is_true()


## Wall off a corridor with a 2-high blocky wall (open only on the +Z side, so
## the detour is unique): the flat route is gone and the next pathfind detours
## around the wall (live blocky reads — no cache to invalidate, D4
## invalidation matrix row 1).
func test_blocky_wall_forces_detour() -> void:
	var solid := {}
	_fill_floor(solid, -5, 5, -5, 5, 0)
	for z in range(-2, 2):
		solid[Vector3i(2, 1, z)] = true
		solid[Vector3i(2, 2, z)] = true
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(_hybrid(solid, {}))
	var path := finder.find_path(Vector3i(0, 1, 0), Vector3i(4, 1, 0))
	assert_int(path.size()).is_greater(5)  # the flat route would be 5 cells
	var crossed_wall := false
	for c in path:
		if c.x == 2 and c.z >= -2 and c.z <= 1:
			crossed_wall = true
	assert_bool(crossed_wall).is_false()
	assert_bool(path.has(Vector3i(2, 1, 2))).is_true()  # through the only gap column


# --- pathfinder: hinted stand-cell resolvers ----------------------------------

## A plate-height Y over a hill column is outside the +/-3 scan window: the
## hint rescues find_stand_cell, and without it the flat assumption fails
## clean (returns the floored base).
func test_find_stand_cell_uses_hint_beyond_scan_window() -> void:
	var heights := {Vector2i(4, 8): {"h": 6.4, "n": Vector3.UP}}
	var predicate := _hybrid({}, heights)
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(predicate)
	finder.set_stand_cell_hint(_fake_hint(heights))
	assert_that(finder.find_stand_cell(Vector3(4, 1.2, 8))).is_equal(Vector3i(4, 6, 8))
	var unhinted: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	unhinted.set_walkability(predicate)
	assert_that(unhinted.find_stand_cell(Vector3(4, 1.2, 8))).is_equal(Vector3i(4, 1, 8))


## Ring search over a sloped neighborhood: the adjacent column's standable
## cell sits at a different Y. The +/-1 probes find it with or without the
## hint — the hint only extends reach beyond one vertical step (the exact
## heightfield stand Y, e.g. the tunnel-vs-roof case below).
func test_ring_search_resolves_derived_stand_y() -> void:
	var heights := {Vector2i(1, 0): {"h": 2.4, "n": Vector3.UP}}
	var solid := {Vector3i(0, 0, 0): true, Vector3i(0, 1, 0): true}  # blocked center
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(_hybrid(solid, heights))
	finder.set_stand_cell_hint(_fake_hint(heights))
	assert_that(finder.find_stand_near_cell(Vector3i(0, 1, 0))).is_equal(Vector3i(1, 2, 0))
	var unhinted: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	unhinted.set_walkability(_hybrid(solid, heights))
	assert_that(unhinted.find_stand_near_cell(Vector3i(0, 1, 0))).is_equal(Vector3i(1, 2, 0))


## Hint MAX (column beyond the smooth terrain) falls back to the same-Y ring
## cell — flat-ground behavior survives where hills don't reach.
func test_ring_search_hint_max_falls_back_to_same_y() -> void:
	var solid := {Vector3i(0, 0, 0): true, Vector3i(0, 1, 0): true, Vector3i(1, 0, 0): true}
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(_hybrid(solid, {}))
	finder.set_stand_cell_hint(_fake_hint({}))
	assert_that(finder.find_stand_near_cell(Vector3i(0, 1, 0))).is_equal(Vector3i(1, 1, 0))


## An excavated tunnel below a hill (h = 16.0) has air at y=13 and y=14, with
## solid terrain at y=12. The hybrid probe must recognise y=13 as a standable
## tunnel floor, while unexcavated solid cells stay unwalkable.
func test_excavated_tunnel_below_hill_is_walkable() -> void:
	var heights := _flat_heights(-3, 3, -3, 3, 16.0)
	# Solid terrain everywhere except the carved tunnel corridor at (0, 13, 0) and head cell (0, 14, 0)
	var is_solid_terrain := func(cell: Vector3i) -> bool:
		if cell.x == 0 and cell.z == 0 and (cell.y == 13 or cell.y == 14):
			return false # Carved tunnel air
		return true # Solid rock

	var probe: Callable = MapWiring.hybrid_ground_probe(
		_fake_get_block_at({}),
		_fake_height_at(heights),
		_MAX_SLOPE_DEG,
		is_solid_terrain
	)

	assert_bool(probe.call(Vector3i(0, 13, 0))).is_true()  # Tunnel floor is walkable
	assert_bool(probe.call(Vector3i(0, 14, 0))).is_false() # Head cell has no floor below
	assert_bool(probe.call(Vector3i(0, 10, 0))).is_false() # Unexcavated solid rock is unwalkable


## When resolving a stand cell for a dig target underground (y=13) below a hill (h=16),
## find_stand_near_cell must choose the adjacent tunnel floor at y=13 rather than
## jumping to the hilltop roof at y=16.
func test_find_stand_near_cell_prefers_local_tunnel_floor_over_hill_roof() -> void:
	var heights := _flat_heights(-3, 3, -3, 3, 16.0)
	# Tunnel carved at y=13 with solid floor at y=12
	var is_solid_terrain := func(cell: Vector3i) -> bool:
		# Target block being mined at (0, 13, 0) is solid
		if cell == Vector3i(0, 13, 0):
			return true
		# Adjacent tunnel cells at (-1, 13, 0), (1, 13, 0), etc. are carved air (and head cells at y=14)
		if cell.y == 13 or cell.y == 14:
			return false
		return true # Floor below and rest of mountain is solid

	var predicate: Callable = MapWiring.hybrid_ground_probe(
		_fake_get_block_at({}),
		_fake_height_at(heights),
		_MAX_SLOPE_DEG,
		is_solid_terrain
	)

	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(predicate)
	finder.set_stand_cell_hint(_fake_hint(heights)) # Hint points to y=16 (roof)

	var resolved_stand := finder.find_stand_near_cell(Vector3i(0, 13, 0))
	assert_int(resolved_stand.y).is_equal(13) # Must stand in the tunnel at y=13, NOT y=16!
	assert_bool(predicate.call(resolved_stand)).is_true()


## A 1-cell wide downward stairway under a hill: colonist paths down step-by-step
## and resolves the stand cell adjacent to the bottom dig target.
func test_one_cell_wide_stairway_down_pathfinding() -> void:
	var heights := _flat_heights(-5, 5, -5, 5, 16.0)
	# 1-cell wide stairway down along +X at z=0:
	# Step 0: stand at (0, 10, 0), air at y=10..12, floor at y=9
	# Step 1: stand at (1, 9, 0), air at y=9..11, floor at y=8
	# Step 2: stand at (2, 8, 0), air at y=8..10, floor at y=7
	# Step 3: stand at (3, 7, 0), air at y=7..9, floor at y=6
	# Step 4 (unmined target block at (4, 6, 0)): solid
	var is_solid_terrain := func(cell: Vector3i) -> bool:
		if cell.z == 0:
			for s in range(4):
				var sx := s
				var stand_y := 10 - s
				if cell.x == sx and cell.y >= stand_y and cell.y <= stand_y + 2:
					return false # Carved 3-high stairway air
		return true # Everything else (including floor below and walls at z!=0) is solid

	var predicate: Callable = MapWiring.hybrid_ground_probe(
		_fake_get_block_at({}),
		_fake_height_at(heights),
		_MAX_SLOPE_DEG,
		is_solid_terrain
	)

	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(predicate)
	finder.set_stand_cell_hint(_fake_hint(heights))

	# All carved stairway stand cells must be walkable
	for s in range(4):
		var stand_cell := Vector3i(s, 10 - s, 0)
		assert_bool(predicate.call(stand_cell)).is_true()

	# Ring search for the unmined target at (4, 6, 0) must find (3, 7, 0)
	var resolved_stand := finder.find_stand_near_cell(Vector3i(4, 6, 0))
	assert_that(resolved_stand).is_equal(Vector3i(3, 7, 0))

	# Full path from top (0, 10, 0) to bottom stand cell (3, 7, 0)
	var path := finder.find_path(Vector3i(0, 10, 0), resolved_stand)
	assert_int(path.size()).is_equal(4)
	assert_that(path[0]).is_equal(Vector3i(0, 10, 0))
	assert_that(path[1]).is_equal(Vector3i(1, 9, 0))
	assert_that(path[2]).is_equal(Vector3i(2, 8, 0))
	assert_that(path[3]).is_equal(Vector3i(3, 7, 0))


# --- lattice-level regression: carve-dilation fringe in walls -------------------
# The tests above stub solidity as clean per-cell booleans; the REAL dig
# pipeline stamps each dug cell's full corner span (SmoothGrid.carve_box ->
# box_sample_targets), which bleeds one lattice plane into the neighbouring
# walls. These fakes replay that lattice so the probe is exercised against
# the geometry the game actually writes (see suite_smooth_grid_test.gd for
# the is_solid_cell unit pins over the same idiom).

const _ROCK_SDF := -2.0


## Lattice stand-in for the voxel tool: sample Dictionary (Vector3i -> float),
## _ROCK_SDF everywhere else.
func _fake_get_voxel_f(samples: Dictionary) -> Callable:
	return func(p: Vector3i) -> float:
		return float(samples.get(p, _ROCK_SDF))


## Stamp one dug cell exactly as the dig pipeline does (MiningSystem carves
## each cell via carve_box(cell, cell + ONE)): the real box_sample_targets
## applied with carve_box's monotonic air-only writes.
func _stamp_dug_cell(samples: Dictionary, cell: Vector3i) -> void:
	var targets := SmoothGrid.box_sample_targets(Vector3(cell), Vector3(cell) + Vector3.ONE)
	for sample: Vector3i in targets:
		samples[sample] = maxf(float(targets[sample]), float(samples.get(sample, _ROCK_SDF)))


## Plain 2-arg height stand-in for SmoothGrid.is_solid_cell (no normals array).
func _fake_height_only(heights: Dictionary) -> Callable:
	return func(x: float, z: float) -> float:
		var col := Vector2i(int(floor(x)), int(floor(z)))
		return NAN if not heights.has(col) else float(heights[col])


## THE wall-fringe regression: a 1-wide stairway dug by the real carve stamps
## makes the wall cells beside every step read hollow to a min-corner probe —
## A* then routed through the wall (flat 1.0 beats the ramp's 3.0 climb) and
## colonists ground against rock with FAIL_OBSTACLE_TOO_HIGH. The whole-cell
## probe must keep the fringe solid so the only route out is the ramp itself.
func test_one_cell_stairway_carve_fringe_stays_unwalkable() -> void:
	# Same geometry as test_one_cell_wide_stairway_down_pathfinding: step s
	# stands at (s, 10-s, 0) with 3-high air above.
	var samples := {}
	for s in range(4):
		for h in range(3):
			_stamp_dug_cell(samples, Vector3i(s, 10 - s + h, 0))

	# Trench columns read their tread height (ray down the open stairwell);
	# every other column is intact hill surface at 16.
	var heights := {}
	var hmap := {}
	for x in range(-5, 6):
		for z in range(-5, 6):
			var h := 16.0 if not (z == 0 and x >= 0 and x <= 3) else float(10 - x)
			heights[Vector2i(x, z)] = {"h": h, "n": Vector3.UP}
			hmap[Vector2i(x, z)] = h

	var is_terrain := func(cell: Vector3i) -> bool:
		return SmoothGrid.is_solid_cell(_fake_get_voxel_f(samples), _fake_height_only(hmap), cell)

	var probe: Callable = MapWiring.hybrid_ground_probe(
		_fake_get_block_at({}),
		_fake_height_at(heights),
		_MAX_SLOPE_DEG,
		is_terrain
	)

	# The ramp itself stays walkable, step by step.
	for s in range(4):
		assert_bool(probe.call(Vector3i(s, 10 - s, 0))).is_true()

	# The wall cells beside every step are NOT walkable: their dilated shared
	# plane no longer reads as hollow once the whole cell is considered.
	for s in range(4):
		assert_bool(probe.call(Vector3i(s, 10 - s, 1))).is_false()
		assert_bool(probe.call(Vector3i(s, 10 - s, -1))).is_false()

	# Headroom air above the treads has no floor below — stays unwalkable.
	for s in range(4):
		assert_bool(probe.call(Vector3i(s, 11 - s, 0))).is_false()
		assert_bool(probe.call(Vector3i(s, 12 - s, 0))).is_false()

	# The path out of the stairwell climbs the ramp exactly — no wall detour.
	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(probe)
	finder.set_stand_cell_hint(_fake_hint(heights))
	var path := finder.find_path(Vector3i(3, 7, 0), Vector3i(0, 10, 0))
	assert_int(path.size()).is_equal(4)
	assert_that(path[0]).is_equal(Vector3i(3, 7, 0))
	assert_that(path[1]).is_equal(Vector3i(2, 8, 0))
	assert_that(path[2]).is_equal(Vector3i(1, 9, 0))
	assert_that(path[3]).is_equal(Vector3i(0, 10, 0))
