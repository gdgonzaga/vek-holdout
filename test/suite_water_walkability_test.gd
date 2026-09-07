extends GdUnitTestSuite

## Verification suite for water walkability, probe rules, and pathfinder cost weighting.

const DOWN := Vector3i(0, -1, 0)
const UP := Vector3i(0, 1, 0)


func test_blocky_ground_probe_water_invariants() -> void:
	var world: Dictionary = {}
	var get_block_at := func(cell: Vector3i) -> String:
		return world.get(cell, "")

	var probe := MapWiring.blocky_ground_probe(get_block_at)

	# 1. Dry ground: solid floor at Y=0, air at Y=1, air at Y=2.
	world[Vector3i(0, 0, 0)] = "solid_stone"
	assert_bool(bool(probe.call(Vector3i(0, 1, 0)))).is_true()

	# 2. Shallow water: solid floor at Y=0, water at Y=1, air at Y=2.
	world[Vector3i(1, 0, 0)] = "solid_stone"
	world[Vector3i(1, 1, 0)] = "water"
	assert_bool(bool(probe.call(Vector3i(1, 1, 0)))).is_true()

	# 3. Floating on deep water: water at Y=1, colonist trying to stand at Y=2.
	assert_bool(bool(probe.call(Vector3i(1, 2, 0)))).is_false()

	# 4. Deep water submerged: solid floor at Y=0, water at Y=1, water at Y=2.
	world[Vector3i(2, 0, 0)] = "solid_stone"
	world[Vector3i(2, 1, 0)] = "water"
	world[Vector3i(2, 2, 0)] = "water"
	assert_bool(bool(probe.call(Vector3i(2, 1, 0)))).is_false()

	# 5. Solid block obstacle at feet: solid block at Y=1.
	world[Vector3i(3, 0, 0)] = "solid_stone"
	world[Vector3i(3, 1, 0)] = "solid_stone"
	assert_bool(bool(probe.call(Vector3i(3, 1, 0)))).is_false()


func test_pathfinder_wades_through_shallow_water() -> void:
	var world: Dictionary = {}
	# Flat solid floor from X=-3 to 3 at Y=0.
	for x in range(-3, 4):
		for z in range(-1, 2):
			world[Vector3i(x, 0, z)] = "stone"

	# Shallow water strip at X=0.
	for z in range(-1, 2):
		world[Vector3i(0, 1, z)] = "water"

	var get_block_at := func(cell: Vector3i) -> String:
		return world.get(cell, "")

	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(MapWiring.blocky_ground_probe(get_block_at))

	var path := finder.find_path(Vector3i(-2, 1, 0), Vector3i(2, 1, 0))
	assert_int(path.size()).is_equal(5)
	assert_bool(path.has(Vector3i(0, 1, 0))).is_true()


func test_pathfinder_prefers_dry_detour_over_water() -> void:
	var world: Dictionary = {}
	# 5x5 platform at Y=0.
	for x in range(-2, 3):
		for z in range(-2, 3):
			world[Vector3i(x, 0, z)] = "stone"

	# Water directly blocking the straight path at X=0, Z=0.
	world[Vector3i(0, 1, 0)] = "water"

	var get_block_at := func(cell: Vector3i) -> String:
		return world.get(cell, "")

	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(MapWiring.blocky_ground_probe(get_block_at))

	# Cost function adds +2.0 cost for water cells (effective 3.0x step cost).
	var cell_cost := func(cell: Vector3i) -> float:
		return 2.0 if world.get(cell, "") == "water" else 0.0
	finder.set_cell_cost(cell_cost)

	# Route from (-1, 1, 0) to (1, 1, 0).
	# Straight path through water: 2 steps, total cost = 1.0 + (1.0 + 2.0) = 4.0.
	# Detour via Z=1: (-1,1,0) -> (0,1,1) [diag 1.414] -> (1,1,0) [diag 1.414] = ~2.828.
	# Detour is significantly cheaper than wading through water!
	var path := finder.find_path(Vector3i(-1, 1, 0), Vector3i(1, 1, 0))
	assert_bool(path.is_empty()).is_false()
	assert_bool(path.has(Vector3i(0, 1, 0))).is_false()


func test_pathfinder_cannot_cross_deep_water() -> void:
	var world: Dictionary = {}
	# Two separated islands: X <= -1 and X >= 1. Gap at X=0 is 2 blocks deep of water.
	for x in range(-3, 0):
		for z in range(-1, 2):
			world[Vector3i(x, 0, z)] = "stone"
	for x in range(1, 4):
		for z in range(-1, 2):
			world[Vector3i(x, 0, z)] = "stone"

	# Deep water chasm at X=0: floor is at Y=-2, water fills Y=-1, Y=0, Y=1.
	for z in range(-1, 2):
		world[Vector3i(0, -2, z)] = "stone"
		world[Vector3i(0, -1, z)] = "water"
		world[Vector3i(0, 0, z)] = "water"
		world[Vector3i(0, 1, z)] = "water"

	var get_block_at := func(cell: Vector3i) -> String:
		return world.get(cell, "")

	var finder: VoxelPathfinder = auto_free(VoxelPathfinder.new())
	finder.set_walkability(MapWiring.blocky_ground_probe(get_block_at))

	var path := finder.find_path(Vector3i(-2, 1, 0), Vector3i(2, 1, 0))
	assert_int(path.size()).is_equal(0)
