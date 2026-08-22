extends GdUnitTestSuite

## Unit tests for the Phase 5 mining dig (docs/TODO.md Phase 5):
## - Data shape: DigToolParams (box/sphere shapes, grid snapping), mining skill,
##   TerrainMaterialDef.yields on the ground material
## - DigAction._apply: carve at the given center/radius or box bounds + yields
##   from the material AT THE DIG POSITION (the RecordingSmoothGrid.material_def seam)
##   + mining XP (the HarvestAction._apply testing seam)
## - DigAction timed path: busy lock while the gauge runs, completion carves
## - SmoothGrid.box_samples: the box-to-samples math the carve and ghost share
## - SmoothGrid.nearest_solid_sample_in: the BOX dig's anchor selection
## - BuildController._calculate_dig_target / _dig_target: cell-center prior +
##   hit-point refinement of the BOX dig

const DIG_TOOL: DigToolParams = preload("res://data/mining/dig_tool.tres")
const GROUND: TerrainMaterialDef = preload("res://data/terrain/materials/ground.tres")
const ROCK: TerrainMaterialDef = preload("res://data/terrain/materials/rock.tres")

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const Doubles = preload("res://test/helpers/doubles.gd")

var _sandbox: ColonySandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)


func after_test() -> void:
	_sandbox.restore()


func test_dig_tool_params_shape() -> void:
	assert_float(DIG_TOOL.work_time).is_greater(0.0)
	assert_int(DIG_TOOL.shape).is_equal(DigToolParams.Shape.BOX)
	assert_vector(DIG_TOOL.box_size).is_equal(Vector3(1.0, 1.0, 1.0))
	assert_bool(DIG_TOOL.snap_grid).is_true()


func test_mining_skill_in_catalog_with_labor() -> void:
	var skill_set := SkillSet.new()
	auto_free(skill_set)
	add_child(skill_set)
	# Fresh set: L1, the 1.0 unskilled baseline — and mining records via labor.
	assert_float(skill_set.get_multiplier("mining")).is_equal(1.0)
	assert_bool(skill_set.record_use_for_labor("mining")).is_true()
	assert_int(skill_set.get_level("mining")).is_equal(1)


func test_ground_material_has_yields() -> void:
	assert_bool(GROUND.yields.is_empty()).is_false()
	for entry: ItemAmount in GROUND.yields:
		assert_object(entry.item_def).is_not_null()
		assert_int(entry.count).is_greater(0)


func test_apply_box_carves_and_grants_yields() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = GROUND
	var center := Vector3(4.5, 2.5, 4.5)

	var action := DigAction.new()
	action._apply(player, grid, center, DIG_TOOL)

	assert_int(grid.box_carves.size()).is_equal(1)
	assert_vector(grid.box_carves[0]["min"]).is_equal(Vector3(4.0, 2.0, 4.0))
	assert_vector(grid.box_carves[0]["max"]).is_equal(Vector3(5.0, 3.0, 5.0))
	var yield_entry: ItemAmount = GROUND.yields[0]
	assert_bool(player.inventory.has_item(yield_entry.item_def.id, yield_entry.count)).is_true()
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(1)


func test_apply_sphere_carves_when_configured() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = GROUND
	var center := Vector3(4.0, 2.0, 4.0)

	var sphere_tool := DigToolParams.new()
	auto_free(sphere_tool)
	sphere_tool.shape = DigToolParams.Shape.SPHERE
	sphere_tool.carve_radius = 1.5

	var action := DigAction.new()
	action._apply(player, grid, center, sphere_tool)

	assert_int(grid.carves.size()).is_equal(1)
	assert_vector(grid.carves[0]["pos"]).is_equal(center)
	assert_float(grid.carves[0]["radius"]).is_equal(1.5)


## Per-position identity: the def at the dig position decides the yields —
## a rock-position dig drops stone even when the grid's default is ground.
func test_apply_yields_come_from_the_dig_position_not_the_default() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = GROUND
	grid.material_def = ROCK

	var action := DigAction.new()
	action._apply(player, grid, Vector3(0.0, -10.0, 0.0), DIG_TOOL)

	var ground_yield: ItemAmount = GROUND.yields[0]
	assert_bool(player.inventory.has_item(ground_yield.item_def.id, ground_yield.count)).is_false()
	var rock_yield: ItemAmount = ROCK.yields[0]
	assert_bool(player.inventory.has_item(rock_yield.item_def.id, rock_yield.count)).is_true()


func test_apply_without_default_material_still_carves() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.default_material = null
	var center := Vector3(1.5, 3.5, 1.5)

	var action := DigAction.new()
	action._apply(player, grid, center, DIG_TOOL)

	# No material identity = no yields, but the carve (and the labor) happened.
	assert_int(grid.box_carves.size()).is_equal(1)
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(1)


func test_timed_dig_locks_busy_then_carves_on_completion() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = GROUND
	var center := Vector3(1.5, 3.5, 1.5)

	var fast_tool := DigToolParams.new()
	auto_free(fast_tool)
	fast_tool.work_time = 0.05
	fast_tool.shape = DigToolParams.Shape.BOX
	fast_tool.box_size = Vector3(1.0, 1.0, 1.0)

	var action := DigAction.new()
	action.begin(player, grid, center, fast_tool)
	assert_bool(player.is_busy()).is_true()
	assert_int(grid.box_carves.size()).is_equal(0)

	var waited := 0.0
	while player.is_busy() and waited < 3.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05

	assert_bool(player.is_busy()).is_false()
	assert_int(grid.box_carves.size()).is_equal(1)
	assert_vector(grid.box_carves[0]["min"]).is_equal(Vector3(1.0, 3.0, 1.0))
	assert_vector(grid.box_carves[0]["max"]).is_equal(Vector3(2.0, 4.0, 2.0))
	var yield_entry: ItemAmount = GROUND.yields[0]
	assert_bool(player.inventory.has_item(yield_entry.item_def.id, yield_entry.count)).is_true()


## box_samples: a snapped 1x1x1 dig (bounds exactly on cell edges) clears ALL
## 8 corner samples of the struck cell — the regression pin for incline-edge
## digs. On a steep face the min-corner sample is already air and the surface
## is held up by a higher corner; clearing only the min corner left the mound
## standing (the silent no-op dig).
func test_box_samples_clears_all_corners_of_the_struck_cell() -> void:
	var samples := SmoothGrid.box_samples(Vector3(4.0, 2.0, 4.0), Vector3(5.0, 3.0, 5.0))
	assert_int(samples.size()).is_equal(8)
	assert_bool(samples.has(Vector3i(4, 2, 4))).is_true()
	assert_bool(samples.has(Vector3i(5, 3, 5))).is_true()
	# The corner above the min sample — the one holding an incline-edge
	# surface up when the min sample is on the air side.
	assert_bool(samples.has(Vector3i(4, 3, 4))).is_true()
	assert_bool(samples.has(Vector3i(5, 2, 5))).is_true()


## box_samples: a snapped 3x3x3 dig covers the 4x4x4 sample span matching the
## ghost's world extent — nothing beyond it.
func test_box_samples_covers_world_extent_for_3x3x3() -> void:
	var samples := SmoothGrid.box_samples(Vector3(3.0, 3.0, 3.0), Vector3(6.0, 6.0, 6.0))
	assert_int(samples.size()).is_equal(64)
	assert_bool(samples.has(Vector3i(3, 3, 3))).is_true()
	assert_bool(samples.has(Vector3i(6, 6, 6))).is_true()
	assert_bool(samples.has(Vector3i(2, 3, 3))).is_false()
	assert_bool(samples.has(Vector3i(7, 6, 6))).is_false()


## box_samples: negative coordinates — a box on the [-3, -2] edges covers the
## samples -3 and -2 per axis (ceil/floor must not truncate the wrong way).
func test_box_samples_negative_coordinates() -> void:
	var samples := SmoothGrid.box_samples(Vector3(-3.0, -3.0, -3.0), Vector3(-2.0, -2.0, -2.0))
	assert_int(samples.size()).is_equal(8)
	assert_bool(samples.has(Vector3i(-3, -2, -3))).is_true()
	assert_bool(samples.has(Vector3i(-2, -3, -2))).is_true()


## box_samples: unsnapped fractional bounds cover the integer samples INSIDE
## the closed box only — sample 4 sits below 4.2 and stays.
func test_box_samples_fractional_bounds() -> void:
	var samples := SmoothGrid.box_samples(Vector3(4.2, 2.0, 4.0), Vector3(5.1, 3.0, 5.0))
	assert_int(samples.size()).is_equal(4)
	assert_bool(samples.has(Vector3i(5, 2, 4))).is_true()
	assert_bool(samples.has(Vector3i(5, 3, 5))).is_true()
	assert_bool(samples.has(Vector3i(4, 2, 4))).is_false()


## The BOX dig target snaps to the CENTER of the struck cell (floor + 0.5) —
## never the nearest lattice vertex — so the ghost box outlines exactly the
## cells carve_box clears. Both call sites (ghost + dig) share this math.
func test_calculate_dig_target_snaps_to_struck_cell_center() -> void:
	var controller := BuildController.new()
	auto_free(controller)
	var straight := {"point": Vector3(4.6, 2.3, -3.7), "normal": Vector3.UP}
	assert_vector(controller._calculate_dig_target(straight)).is_equal(Vector3(4.5, 2.5, -3.5))
	# Diagonal normal nudging the sample across the origin: floor must land in
	# cell (-1, -1, -1), i.e. the negative-side cell, not round-to-zero.
	var diagonal := {"point": Vector3(0.0, 0.0, 0.0), "normal": Vector3(1.0, 1.0, 1.0).normalized()}
	assert_vector(controller._calculate_dig_target(diagonal)).is_equal(Vector3(-0.5, -0.5, -0.5))


## nearest_solid_sample_in: the anchor is the nearest SOLID sample to the hit
## point — the incline-edge regression, where the struck cell's min sample is
## air and the surface is held up by the corner above it.
func test_nearest_solid_sample_finds_the_corner_holding_the_surface() -> void:
	var solids := {Vector3i(4, 3, 4): true}
	var pick := func(pos: Vector3i) -> bool: return solids.has(pos)
	var anchor := SmoothGrid.nearest_solid_sample_in(Vector3(4.5, 2.6, 4.5), pick)
	assert_vector(anchor).is_equal(Vector3(4, 3, 4))


## The ghost tracks the crosshair: as the hit point slides inside the struck
## cell, the anchor steps to whichever solid corner is nearest.
func test_nearest_solid_sample_tracks_the_hit_point() -> void:
	var solids := {Vector3i(4, 2, 4): true, Vector3i(5, 2, 4): true}
	var pick := func(pos: Vector3i) -> bool: return solids.has(pos)
	assert_vector(SmoothGrid.nearest_solid_sample_in(Vector3(4.1, 2.5, 4.5), pick)).is_equal(Vector3(4, 2, 4))
	assert_vector(SmoothGrid.nearest_solid_sample_in(Vector3(4.9, 2.5, 4.5), pick)).is_equal(Vector3(5, 2, 4))


## The struck cell's own corners win over ring candidates — the "ghost snaps
## two cubes away" regression: a solid sample further out must not steal the
## anchor from the corner under the crosshair.
func test_nearest_solid_sample_prefers_struck_cell_over_ring() -> void:
	var solids := {Vector3i(4, 2, 4): true, Vector3i(6, 3, 5): true}
	var pick := func(pos: Vector3i) -> bool: return solids.has(pos)
	var anchor := SmoothGrid.nearest_solid_sample_in(Vector3(4.6, 2.6, 4.6), pick)
	assert_vector(anchor).is_equal(Vector3(4, 2, 4))


## All-air surroundings: the position comes back unchanged (aim at air —
## the dig clears nothing), while the one-ring widening still answers grazing
## hits whose struck cell is all-air.
func test_nearest_solid_sample_all_air_falls_back_to_ring_then_position() -> void:
	var none_solid := func(_pos: Vector3i) -> bool: return false
	var pos := Vector3(4.5, 2.5, 4.5)
	assert_vector(SmoothGrid.nearest_solid_sample_in(pos, none_solid)).is_equal(pos)
	var solids := {Vector3i(6, 3, 5): true}
	var ring_pick := func(p: Vector3i) -> bool: return solids.has(p)
	assert_vector(SmoothGrid.nearest_solid_sample_in(Vector3(4.9, 2.6, 4.6), ring_pick)).is_equal(Vector3(6, 3, 5))


## _dig_target: the BOX refinement runs from the ACTUAL hit point — with no
## live voxel tool the grid hands back the nudged hit point unchanged (the
## no-refinement fallback), not the cell-center prior.
func test_dig_target_refines_from_the_hit_point() -> void:
	var controller := BuildController.new()
	auto_free(controller)
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	var target := controller._dig_target(grid, {"point": Vector3(4.6, 2.3, 4.5), "normal": Vector3.UP})
	assert_vector(target).is_equal(Vector3(4.5, 2.5, 4.5))

# ── Dig Box & MiningSystem Tests ──────────────────────────────────────────────

## Mock grid adapter to record block removals
class MockVoxelGridAdapter extends VoxelGridAdapter:
	var removed_blocks: Array[Vector3i] = []
	var mock_blocks: Dictionary = {}
	var _mock_smooth: Doubles.RecordingSmoothGrid
	var mock_terrain: Dictionary = {}

	func _init(smooth: Doubles.RecordingSmoothGrid = null) -> void:
		_mock_smooth = smooth

	func get_block_at(cell: Vector3i) -> String:
		return mock_blocks.get(cell, "")

	func remove_block_at(cell: Vector3i) -> void:
		removed_blocks.append(cell)
		mock_blocks.erase(cell)

	func get_smooth_grid() -> SmoothGrid:
		return _mock_smooth

	func is_terrain_at(cell: Vector3i, threshold: float = 0.5) -> bool:
		if not mock_terrain.is_empty():
			return mock_terrain.get(cell, false)
		return super.is_terrain_at(cell, threshold)


func test_mining_system_spawns_and_deduplicates_designation_markers() -> void:
	var root := Node3D.new()
	auto_free(root)
	add_child(root)

	var mining_sys := MiningSystem.new()
	auto_free(mining_sys)
	root.add_child(mining_sys)

	var cells: Array[Vector3i] = [Vector3i(1, 2, 3), Vector3i(4, 5, 6)]
	EventBus.dig_box_designated.emit(cells)

	var container := root.get_node_or_null("DesignationContainer") as Node3D
	assert_object(container).is_not_null()
	assert_int(container.get_child_count()).is_equal(2)
	assert_object(container.get_node_or_null("Marker_1_2_3")).is_not_null()
	assert_object(container.get_node_or_null("Marker_4_5_6")).is_not_null()

	# Re-emit with one duplicate and one new cell
	EventBus.dig_box_designated.emit([Vector3i(1, 2, 3), Vector3i(7, 8, 9)])
	assert_int(container.get_child_count()).is_equal(3)
	assert_object(container.get_node_or_null("Marker_7_8_9")).is_not_null()


func test_mining_system_on_dig_job_completed_frees_marker_and_carves() -> void:
	var root := Node3D.new()
	auto_free(root)
	add_child(root)

	var smooth: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(smooth)
	var adapter := MockVoxelGridAdapter.new(smooth)
	auto_free(adapter)

	var mining_sys := MiningSystem.new()
	auto_free(mining_sys)
	mining_sys.grid_adapter = adapter
	root.add_child(mining_sys)

	# Spawn a marker
	EventBus.dig_box_designated.emit([Vector3i(2, 3, 4)])
	var container := root.get_node_or_null("DesignationContainer") as Node3D
	assert_object(container.get_node_or_null("Marker_2_3_4")).is_not_null()

	# Fire completion
	EventBus.dig_job_completed.emit(Vector3i(2, 3, 4))
	await get_tree().process_frame

	# Marker should be queued for deletion / null
	var marker := container.get_node_or_null("Marker_2_3_4")
	assert_bool(marker == null or marker.is_queued_for_deletion()).is_true()

	# Adapter and smooth grid should record removal/carve
	assert_int(adapter.removed_blocks.size()).is_equal(1)
	assert_vector(adapter.removed_blocks[0]).is_equal(Vector3i(2, 3, 4))
	assert_int(smooth.box_carves.size()).is_equal(1)
	assert_vector(smooth.box_carves[0]["min"]).is_equal(Vector3(2, 3, 4))
	assert_vector(smooth.box_carves[0]["max"]).is_equal(Vector3(3, 4, 5))


func test_dig_box_designated_spawns_jobs_on_colony_board() -> void:
	var cells: Array = [Vector3i(10, 1, 10), Vector3i(11, 1, 10)]
	EventBus.dig_box_designated.emit(cells)

	var available_jobs: Array[Job] = Colony.job_board.get_jobs()
	var dig_jobs: Array = []
	for j in available_jobs:
		var job := j as Job
		if job != null and job.def != null and job.def.id == "dig":
			dig_jobs.append(job)
	assert_int(dig_jobs.size()).is_equal(2)


func test_dig_job_def_legs_and_completion_signal() -> void:
	var dig_def: JobDef = preload("res://data/jobs/dig.tres")
	var target_cell := Vector3i(5, 1, 5)
	var job := Job.from_def(dig_def)
	job.anchor_cell = target_cell
	job.location = Vector3(target_cell) + Vector3(0.5, 0.5, 0.5)
	var colonist := _sandbox.make_colonist()

	# Leg: travels to location
	var leg := dig_def.get_next_leg(colonist, job)
	assert_object(leg).is_not_null()
	assert_vector(leg.location).is_equal(job.location)

	# Begin work duration
	var duration := dig_def.begin(colonist, leg, job)
	assert_float(duration).is_greater(0.0)

	# Complete work
	var counter := Doubles.SignalCounter.new(EventBus.dig_job_completed)
	dig_def.complete(colonist, leg, job)
	assert_int(counter.read()).is_equal(1)
	assert_bool(dig_def.should_close(job)).is_true()


func test_dig_box_controller_dominant_cardinal() -> void:
	assert_vector(DigBoxController.get_dominant_cardinal(Vector3(0.9, 0.1, 0.1))).is_equal(Vector3i(1, 0, 0))
	assert_vector(DigBoxController.get_dominant_cardinal(Vector3(-0.9, 0.1, 0.1))).is_equal(Vector3i(-1, 0, 0))
	assert_vector(DigBoxController.get_dominant_cardinal(Vector3(0.1, 0.9, 0.1))).is_equal(Vector3i(0, 1, 0))
	assert_vector(DigBoxController.get_dominant_cardinal(Vector3(0.1, -0.9, 0.1))).is_equal(Vector3i(0, -1, 0))
	assert_vector(DigBoxController.get_dominant_cardinal(Vector3(0.1, 0.1, 0.9))).is_equal(Vector3i(0, 0, 1))
	assert_vector(DigBoxController.get_dominant_cardinal(Vector3(0.1, 0.1, -0.9))).is_equal(Vector3i(0, 0, -1))


func test_mining_system_clean_air_markers_frees_markers_on_air_terrain() -> void:
	var root := Node3D.new()
	auto_free(root)
	add_child(root)

	var smooth: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(smooth)
	var adapter := MockVoxelGridAdapter.new(smooth)
	auto_free(adapter)
	adapter.mock_terrain[Vector3i(1, 2, 3)] = true
	adapter.mock_terrain[Vector3i(4, 5, 6)] = true

	var mining_sys := MiningSystem.new()
	auto_free(mining_sys)
	mining_sys.set_grid_adapter(adapter)
	root.add_child(mining_sys)

	# Spawn markers
	EventBus.dig_box_designated.emit([Vector3i(1, 2, 3), Vector3i(4, 5, 6)])
	var container := root.get_node_or_null("DesignationContainer") as Node3D
	assert_object(container.get_node_or_null("Marker_1_2_3")).is_not_null()
	assert_object(container.get_node_or_null("Marker_4_5_6")).is_not_null()

	# Simulate voxel (1, 2, 3) dug out to air
	adapter.mock_terrain[Vector3i(1, 2, 3)] = false
	mining_sys.clean_air_markers()
	await get_tree().process_frame

	var marker1 := container.get_node_or_null("Marker_1_2_3")
	var marker2 := container.get_node_or_null("Marker_4_5_6")
	assert_bool(marker1 == null or marker1.is_queued_for_deletion()).is_true()
	assert_bool(marker2 != null and not marker2.is_queued_for_deletion()).is_true()


func test_dig_job_def_checks_colony_is_terrain_at() -> void:
	var dig_def: JobDef = preload("res://data/jobs/dig.tres")
	var target_cell := Vector3i(8, 2, 8)
	var job := Job.from_def(dig_def)
	job.anchor_cell = target_cell
	job.location = Vector3(target_cell) + Vector3(0.5, 0.5, 0.5)
	var colonist := _sandbox.make_colonist()

	# Initially terrain is present
	Colony.set_terrain_predicate(func(c: Vector3i) -> bool: return c == target_cell)
	assert_bool(dig_def.is_available(job)).is_true()
	assert_bool(dig_def.should_close(job)).is_false()
	assert_object(dig_def.get_next_leg(colonist, job)).is_not_null()

	# Terrain is mined to air
	Colony.set_terrain_predicate(func(_c: Vector3i) -> bool: return false)
	assert_bool(dig_def.is_available(job)).is_false()
	assert_bool(dig_def.should_close(job)).is_true()
	assert_object(dig_def.get_next_leg(colonist, job)).is_null()


# ── Direct LMB Mining & Damage Tests ─────────────────────────────────────────

func test_smooth_grid_apply_damage_multi_hit_destroys_dirt() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = GROUND
	var target_cell := Vector3i(2, 3, 4)

	# Hit 1: 50 damage to 100 HP dirt -> 50 HP left, not destroyed
	var res1 := grid.apply_damage_at(target_cell, 50, player)
	assert_bool(res1["destroyed"]).is_false()
	assert_int(res1["remaining_hp"]).is_equal(50)
	assert_int(res1["max_hp"]).is_equal(100)
	assert_int(grid.box_carves.size()).is_equal(0)
	var yield_entry: ItemAmount = GROUND.yields[0]
	assert_bool(player.inventory.has_item(yield_entry.item_def.id, yield_entry.count)).is_false()
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(0)

	# Hit 2: another 50 damage -> destroyed, carved, yields granted, skill recorded
	var res2 := grid.apply_damage_at(target_cell, 50, player)
	assert_bool(res2["destroyed"]).is_true()
	assert_int(res2["remaining_hp"]).is_equal(0)
	assert_int(grid.box_carves.size()).is_equal(1)
	assert_vector(grid.box_carves[0]["min"]).is_equal(Vector3(2, 3, 4))
	assert_vector(grid.box_carves[0]["max"]).is_equal(Vector3(3, 4, 5))
	assert_bool(player.inventory.has_item(yield_entry.item_def.id, yield_entry.count)).is_true()
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(1)


func test_smooth_grid_apply_damage_on_rock_takes_6_hits() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = ROCK # 300 HP
	var target_cell := Vector3i(10, 5, 10)

	# 5 hits @ 50 dmg = 250 dmg -> 50 HP remaining
	for i in 5:
		var res := grid.apply_damage_at(target_cell, 50, player)
		assert_bool(res["destroyed"]).is_false()
	assert_int(grid.get_hp_at(target_cell)).is_equal(50)
	assert_int(grid.box_carves.size()).is_equal(0)

	# 6th hit -> 300 dmg total -> destroyed
	var res6 := grid.apply_damage_at(target_cell, 50, player)
	assert_bool(res6["destroyed"]).is_true()
	assert_int(grid.box_carves.size()).is_equal(1)
	var rock_yield: ItemAmount = ROCK.yields[0]
	assert_bool(player.inventory.has_item(rock_yield.item_def.id, rock_yield.count)).is_true()


func test_smooth_grid_damage_decay_heals_over_time() -> void:
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = GROUND # 100 HP, 0.25 min full heal
	var target_cell := Vector3i(7, 8, 9)

	# Hit once for 50 dmg
	grid.apply_damage_at(target_cell, 50)
	assert_bool(grid._hp_by_pos.has(target_cell)).is_true()
	assert_int(grid.get_hp_at(target_cell)).is_equal(50)

	# Simulate 16 seconds passed (beyond the 15s full heal time)
	grid._hp_by_pos[target_cell]["last_hit_ms"] = Time.get_ticks_msec() - 16000

	# Querying HP should show full heal and pruned entry
	assert_int(grid.get_hp_at(target_cell)).is_equal(100)
	assert_bool(grid._hp_by_pos.has(target_cell)).is_false()


func test_smooth_grid_no_heal_when_minutes_to_full_heal_is_zero() -> void:
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	var asphalt := TerrainMaterialDef.new()
	auto_free(asphalt)
	asphalt.id = "asphalt"
	asphalt.hp = 200
	asphalt.minutes_to_full_heal = 0.0 # Non-healing material
	grid.material_def = asphalt
	var target_cell := Vector3i(1, 1, 1)

	# Hit once for 50 dmg
	grid.apply_damage_at(target_cell, 50)
	assert_int(grid.get_hp_at(target_cell)).is_equal(150)

	# Simulate 60 seconds passed
	grid._hp_by_pos[target_cell]["last_hit_ms"] = Time.get_ticks_msec() - 60000

	# Querying HP should still be 150 (damage preserved, no decay)
	assert_int(grid.get_hp_at(target_cell)).is_equal(150)
	assert_bool(grid._hp_by_pos.has(target_cell)).is_true()


func test_smooth_grid_spawns_and_updates_damage_decal() -> void:
	var root := Node3D.new()
	auto_free(root)
	add_child(root)

	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	root.add_child(grid)
	grid.material_def = ROCK # 300 HP

	var target_cell := Vector3i(3, 3, 3)

	# Hit 1: 50 dmg (16.7% dmg) -> Decal spawned at Stage 0
	grid.apply_damage_at(target_cell, 50)
	assert_bool(grid._damage_decals.has(target_cell)).is_true()
	var decal: Decal = grid._damage_decals[target_cell]
	assert_object(decal).is_not_null()
	assert_vector(decal.position).is_equal(Vector3(3.5, 3.5, 3.5))
	assert_vector(decal.size).is_equal(Vector3(1.2, 1.2, 1.2))
	assert_object(decal.texture_albedo).is_equal(SmoothGrid._get_crack_texture(0))

	# Hit 3: 150 dmg (50% dmg) -> Decal advances to Stage 1
	grid.apply_damage_at(target_cell, 100)
	assert_object(decal.texture_albedo).is_equal(SmoothGrid._get_crack_texture(1))

	# Hit 5: 250 dmg (83.3% dmg) -> Decal advances to Stage 2
	grid.apply_damage_at(target_cell, 100)
	assert_object(decal.texture_albedo).is_equal(SmoothGrid._get_crack_texture(2))

	# Hit 6: 300 dmg (destroyed) -> Decal removed & freed
	grid.apply_damage_at(target_cell, 50)
	assert_bool(grid._damage_decals.has(target_cell)).is_false()
	assert_bool(decal.is_queued_for_deletion()).is_true()


func test_smooth_grid_removes_damage_decal_on_full_regeneration() -> void:
	var root := Node3D.new()
	auto_free(root)
	add_child(root)

	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	root.add_child(grid)
	grid.material_def = GROUND # 100 HP, 0.25 min heal

	var target_cell := Vector3i(6, 6, 6)

	# Hit once for 50 dmg -> Decal spawned
	grid.apply_damage_at(target_cell, 50)
	assert_bool(grid._damage_decals.has(target_cell)).is_true()
	var decal: Decal = grid._damage_decals[target_cell]
	assert_object(decal).is_not_null()

	# Simulate 16 seconds passed (fully healed)
	grid._hp_by_pos[target_cell]["last_hit_ms"] = Time.get_ticks_msec() - 16000

	# Query HP -> triggers regeneration cleanup and removes decal
	assert_int(grid.get_hp_at(target_cell)).is_equal(100)
	assert_bool(grid._damage_decals.has(target_cell)).is_false()
	assert_bool(decal.is_queued_for_deletion()).is_true()
