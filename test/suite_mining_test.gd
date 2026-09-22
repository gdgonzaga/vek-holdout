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

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const Doubles = preload("res://test/helpers/doubles.gd")
const TerrainFixtures = preload("res://test/helpers/terrain_fixtures.gd")
const JobFixtures = preload("res://test/helpers/job_fixtures.gd")

var _sandbox: ColonySandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)


func after_test() -> void:
	_sandbox.restore()


func test_mining_skill_in_catalog_with_labor() -> void:
	var skill_set := SkillSet.new()
	auto_free(skill_set)
	add_child(skill_set)
	# Fresh set: L1, the 1.0 unskilled baseline — and mining records via labor.
	assert_float(skill_set.get_multiplier("mining")).is_equal(1.0)
	assert_bool(skill_set.record_use_for_labor("mining")).is_true()
	assert_int(skill_set.get_level("mining")).is_equal(1)


func test_apply_box_carves_and_grants_yields() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	var soil := TerrainFixtures.material("test_soft", 100, {"test_soft_item": 2})
	grid.material_def = soil
	var center := Vector3(4.5, 2.5, 4.5)

	var action := DigAction.new()
	action._apply(player, grid, center, TerrainFixtures.dig_tool())

	assert_int(grid.box_carves.size()).is_equal(1)
	assert_vector(grid.box_carves[0]["min"]).is_equal(Vector3(4.0, 2.0, 4.0))
	assert_vector(grid.box_carves[0]["max"]).is_equal(Vector3(5.0, 3.0, 5.0))
	var yield_entry: ItemAmount = soil.yields[0]
	var world_items := get_tree().get_nodes_in_group("world_items")
	assert_int(world_items.size()).is_greater_equal(1)
	var dropped_item := world_items[-1] as WorldItem
	assert_str(dropped_item.item_id).is_equal(yield_entry.item_def.id)
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(1)


func test_apply_sphere_carves_when_configured() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.material_def = TerrainFixtures.material("test_soft", 100, {"test_soft_item": 2})
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


## Per-position identity: the def at the dig position decides the yields — a
## hard-material-position dig drops that material's item even when the grid's
## default was set to a different (soft) material first.
func test_apply_yields_come_from_the_dig_position_not_the_default() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	var soft := TerrainFixtures.material("test_soft", 100, {"test_soft_item": 2})
	var hard := TerrainFixtures.material("test_hard", 300, {"test_hard_item": 1})
	grid.material_def = soft
	grid.material_def = hard

	var action := DigAction.new()
	action._apply(player, grid, Vector3(0.0, -10.0, 0.0), TerrainFixtures.dig_tool())

	var soft_yield: ItemAmount = soft.yields[0]
	assert_bool(player.inventory.has_item(soft_yield.item_def.id, soft_yield.count)).is_false()
	var hard_yield: ItemAmount = hard.yields[0]
	var world_items_hard := get_tree().get_nodes_in_group("world_items")
	assert_int(world_items_hard.size()).is_greater_equal(1)
	var dropped_hard := world_items_hard[-1] as WorldItem
	assert_str(dropped_hard.item_id).is_equal(hard_yield.item_def.id)


func test_apply_without_default_material_still_carves() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	grid.default_material = null
	var center := Vector3(1.5, 3.5, 1.5)

	var action := DigAction.new()
	action._apply(player, grid, center, TerrainFixtures.dig_tool())

	# No material identity = no yields, but the carve (and the labor) happened.
	assert_int(grid.box_carves.size()).is_equal(1)
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(1)


func test_timed_dig_locks_busy_then_carves_on_completion() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	var soil := TerrainFixtures.material("test_soft", 100, {"test_soft_item": 2})
	grid.material_def = soil
	var center := Vector3(1.5, 3.5, 1.5)

	var fast_tool := TerrainFixtures.dig_tool(0.05)

	var action := DigAction.new()
	action.begin(player, grid, center, fast_tool)
	assert_bool(player.is_busy()).is_true()
	assert_int(grid.box_carves.size()).is_equal(0)

	# Bounded frame wait for the gauge to settle (Hard rule 8/H4: no create_timer wall clock);
	# the gauge advances on _process, so process_frame is the tick that moves it.
	const MAX_FRAMES_TO_WAIT := 240
	var frames_waited := 0
	while player.is_busy() and frames_waited < MAX_FRAMES_TO_WAIT:
		await get_tree().process_frame
		frames_waited += 1

	assert_bool(player.is_busy()).is_false()
	assert_int(frames_waited).is_less(MAX_FRAMES_TO_WAIT)
	assert_int(grid.box_carves.size()).is_equal(1)
	assert_vector(grid.box_carves[0]["min"]).is_equal(Vector3(1.0, 3.0, 1.0))
	assert_vector(grid.box_carves[0]["max"]).is_equal(Vector3(2.0, 4.0, 2.0))
	var yield_entry: ItemAmount = soil.yields[0]
	var world_items := get_tree().get_nodes_in_group("world_items")
	assert_int(world_items.size()).is_greater_equal(1)
	var dropped_item := world_items[-1] as WorldItem
	assert_str(dropped_item.item_id).is_equal(yield_entry.item_def.id)


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


## box_sample_targets: a dug cell's lowest plane is stamped 0.0 (floor exactly
## on the integer grid — SDF 0 is surface), everything above gets the hard
## AIR stamp. These targets are what bleed one lattice plane into the
## neighbouring walls, so they feed the fringe-solidity pins in
## suite_smooth_grid_test.gd.
func test_box_sample_targets_floor_plane_zero_rest_air() -> void:
	var targets := SmoothGrid.box_sample_targets(Vector3(4.0, 2.0, 4.0), Vector3(5.0, 3.0, 5.0))
	assert_int(targets.size()).is_equal(8)
	assert_float(targets[Vector3i(4, 2, 4)]).is_equal(0.0)
	assert_float(targets[Vector3i(5, 2, 5)]).is_equal(0.0)
	assert_float(targets[Vector3i(4, 3, 4)]).is_equal(SmoothGrid.AIR_DENSITY)
	assert_float(targets[Vector3i(5, 3, 5)]).is_equal(SmoothGrid.AIR_DENSITY)


## box_sample_targets: an empty sample span (box between lattice samples)
## yields no targets — carve_box early-returns without evicting or emitting.
func test_box_sample_targets_empty_span() -> void:
	var targets := SmoothGrid.box_sample_targets(Vector3(4.1, 2.1, 4.1), Vector3(4.9, 2.9, 4.9))
	assert_int(targets.size()).is_equal(0)


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


func test_dig_job_def_completion_signal() -> void:
	var target_cell := Vector3i(5, 1, 5)
	var counter := Doubles.SignalCounter.new(EventBus.dig_job_completed)
	EventBus.dig_job_completed.emit(target_cell)
	assert_int(counter.read()).is_equal(1)


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
	var dig_def: JobDef = JobFixtures.dig()
	var target_cell := Vector3i(8, 2, 8)
	var job := Job.from_def(dig_def)
	job.anchor_cell = target_cell
	job.location = Vector3(target_cell) + Vector3(0.5, 0.5, 0.5)
	var colonist := _sandbox.make_colonist()

	# Initially terrain is present
	Colony.set_terrain_predicate(func(c: Vector3i) -> bool: return c == target_cell)
	assert_bool(dig_def.is_available(job)).is_true()
	assert_bool(dig_def.should_close(job)).is_false()

	# Terrain is mined to air
	Colony.set_terrain_predicate(func(_c: Vector3i) -> bool: return false)
	assert_bool(dig_def.is_available(job)).is_false()
	assert_bool(dig_def.should_close(job)).is_true()


## A buried underground dig job (no walkable adjacent cells) is unavailable
## until excavation reaches a neighbour and makes it walkable.
func test_dig_job_def_buried_job_gated_by_walkable_neighbor() -> void:
	var dig_def: JobDef = JobFixtures.dig()
	var target_cell := Vector3i(1, 3, 7)
	var job := Job.from_def(dig_def)
	job.anchor_cell = target_cell
	job.location = Vector3(target_cell) + Vector3(0.5, 0.5, 0.5)
	var colonist := _sandbox.make_colonist()

	Colony.set_terrain_predicate(func(c: Vector3i) -> bool: return true)
	# Initially, completely buried in solid rock: no walkable stand cells
	var walkable_cells := {}
	Colony.set_walkability_predicate(func(c: Vector3i) -> bool: return walkable_cells.has(c))

	# Unreachable: not available, but should NOT close/cancel (waits for excavation)
	assert_bool(dig_def.is_available(job)).is_false()
	assert_bool(dig_def.should_close(job)).is_false()

	# Excavation carves the step above / adjacent at (1, 4, 7) into a walkable stand cell
	walkable_cells[Vector3i(1, 4, 7)] = true
	assert_bool(dig_def.is_available(job)).is_true()
	assert_bool(dig_def.should_close(job)).is_false()


# ── Direct LMB Mining & Damage Tests ─────────────────────────────────────────

## Multi-hit destroy: the exact-HP-remaining boundary must stay on the "not
## destroyed" side of hp <= 0 — a fixture landing precisely on 1 hp remaining
## after a hit is the regression pin for an off-by-one destroy threshold
## (see the T7 mutation check in the phase hand-back).
func test_smooth_grid_apply_damage_multi_hit_destroys_at_zero_hp() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	var soil := TerrainFixtures.material("test_soft", 101, {"test_soft_item": 2})
	grid.material_def = soil
	var target_cell := Vector3i(2, 3, 4)

	# Hit 1: 50 damage off 101 hp -> 51 hp left, not destroyed
	var res1 := grid.apply_damage_at(target_cell, 50, player)
	assert_bool(res1["destroyed"]).is_false()
	assert_int(res1["remaining_hp"]).is_equal(51)
	assert_int(res1["max_hp"]).is_equal(101)
	assert_int(grid.box_carves.size()).is_equal(0)
	var yield_entry: ItemAmount = soil.yields[0]
	assert_bool(player.inventory.has_item(yield_entry.item_def.id, yield_entry.count)).is_false()
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(0)

	# Hit 2: another 50 damage -> exactly 1 hp left, still not destroyed
	var res2 := grid.apply_damage_at(target_cell, 50, player)
	assert_bool(res2["destroyed"]).is_false()
	assert_int(res2["remaining_hp"]).is_equal(1)
	assert_int(grid.box_carves.size()).is_equal(0)

	# Hit 3: final 50 damage -> destroyed, carved, yields granted, skill recorded
	var res3 := grid.apply_damage_at(target_cell, 50, player)
	assert_bool(res3["destroyed"]).is_true()
	assert_int(res3["remaining_hp"]).is_equal(0)
	assert_int(grid.box_carves.size()).is_equal(1)
	assert_vector(grid.box_carves[0]["min"]).is_equal(Vector3(2, 3, 4))
	assert_vector(grid.box_carves[0]["max"]).is_equal(Vector3(3, 4, 5))
	var world_items := get_tree().get_nodes_in_group("world_items")
	assert_int(world_items.size()).is_greater_equal(1)
	var dropped_item := world_items[-1] as WorldItem
	assert_str(dropped_item.item_id).is_equal(yield_entry.item_def.id)
	assert_int(_sandbox.skill_uses(player.skill_set, "mining")).is_equal(1)


func test_smooth_grid_apply_damage_takes_hp_over_swing_damage_hits() -> void:
	var player := _sandbox.make_player()
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	var ore := TerrainFixtures.material("test_hard", 300, {"test_hard_item": 2}) # 300 HP
	grid.material_def = ore
	var target_cell := Vector3i(10, 5, 10)

	# 5 hits @ 50 dmg = 250 dmg -> 50 HP remaining (300 hp needs ceil(300 / 50) == 6 hits total)
	for i in 5:
		var res := grid.apply_damage_at(target_cell, 50, player)
		assert_bool(res["destroyed"]).is_false()
	assert_int(grid.get_hp_at(target_cell)).is_equal(50)
	assert_int(grid.box_carves.size()).is_equal(0)

	# 6th hit -> 300 dmg total -> destroyed
	var res6 := grid.apply_damage_at(target_cell, 50, player)
	assert_bool(res6["destroyed"]).is_true()
	assert_int(grid.box_carves.size()).is_equal(1)
	var ore_yield: ItemAmount = ore.yields[0]
	var world_items_ore := get_tree().get_nodes_in_group("world_items")
	assert_int(world_items_ore.size()).is_greater_equal(1)
	var dropped_ore := world_items_ore[-1] as WorldItem
	assert_str(dropped_ore.item_id).is_equal(ore_yield.item_def.id)


func test_smooth_grid_damage_decay_heals_over_time() -> void:
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	var soil := TerrainFixtures.material("test_soft", 100, {"test_soft_item": 2}, 0.25) # 100 HP, 0.25 min full heal
	grid.material_def = soil
	var target_cell := Vector3i(7, 8, 9)

	# Hit once for 50 dmg
	grid.apply_damage_at(target_cell, 50)
	assert_bool(grid._hp_by_pos.has(target_cell)).is_true()
	assert_int(grid.get_hp_at(target_cell)).is_equal(50)

	# Push the last-hit timestamp past the fixture's own heal window (grace period + full heal
	# time + 1s margin), derived from the fixture instead of a hard-coded offset.
	var heal_seconds: float = soil.minutes_to_full_heal * 60.0
	var elapsed_ms: int = int((heal_seconds + SmoothGrid.HEAL_GRACE_PERIOD_SEC + 1.0) * 1000.0)
	grid._hp_by_pos[target_cell]["last_hit_ms"] = Time.get_ticks_msec() - elapsed_ms

	# Querying HP should show full heal and pruned entry
	assert_int(grid.get_hp_at(target_cell)).is_equal(100)
	assert_bool(grid._hp_by_pos.has(target_cell)).is_false()


func test_smooth_grid_no_heal_when_minutes_to_full_heal_is_zero() -> void:
	var grid: Doubles.RecordingSmoothGrid = Doubles.RecordingSmoothGrid.new()
	auto_free(grid)
	var never_heals := TerrainFixtures.material("test_norecover", 200, {}, 0.0) # Non-healing material
	grid.material_def = never_heals
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
	var ore := TerrainFixtures.material("test_hard", 300, {"test_hard_item": 1}) # 300 HP
	grid.material_def = ore

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
	var soil := TerrainFixtures.material("test_soft", 100, {"test_soft_item": 2}, 0.25) # 100 HP, 0.25 min heal
	grid.material_def = soil

	var target_cell := Vector3i(6, 6, 6)

	# Hit once for 50 dmg -> Decal spawned
	grid.apply_damage_at(target_cell, 50)
	assert_bool(grid._damage_decals.has(target_cell)).is_true()
	var decal: Decal = grid._damage_decals[target_cell]
	assert_object(decal).is_not_null()

	# Push the last-hit timestamp past the fixture's own heal window (fully healed), derived
	# from the fixture instead of a hard-coded offset.
	var heal_seconds: float = soil.minutes_to_full_heal * 60.0
	var elapsed_ms: int = int((heal_seconds + SmoothGrid.HEAL_GRACE_PERIOD_SEC + 1.0) * 1000.0)
	grid._hp_by_pos[target_cell]["last_hit_ms"] = Time.get_ticks_msec() - elapsed_ms

	# Query HP -> triggers regeneration cleanup and removes decal
	assert_int(grid.get_hp_at(target_cell)).is_equal(100)
	assert_bool(grid._damage_decals.has(target_cell)).is_false()
	assert_bool(decal.is_queued_for_deletion()).is_true()


func test_dig_box_stairway_coordinate_generation() -> void:
	var start := Vector3i(10, 20, 30)
	var fwd := Vector3i.FORWARD # (0, 0, -1)
	# width_dir = (0, 0, -1) x (0, 1, 0) = (1, 0, 0)
	var coords: Array[Vector3i] = DigBoxController.get_stairway_coordinates(start, fwd, 3)

	# 3 steps * 3 high * 2 wide = 18 unique voxels
	assert_int(coords.size()).is_equal(18)

	# Step 0 (s=0): Y in [20, 22], Z = 30, X in [10, 11]
	for h in range(3):
		for w in range(2):
			assert_bool(coords.has(Vector3i(10 + w, 20 + h, 30))).is_true()

	# Step 1 (s=1): Y in [19, 21], Z = 29, X in [10, 11]
	for h in range(3):
		for w in range(2):
			assert_bool(coords.has(Vector3i(10 + w, 19 + h, 29))).is_true()

	# Step 2 (s=2): Y in [18, 20], Z = 28, X in [10, 11]
	for h in range(3):
		for w in range(2):
			assert_bool(coords.has(Vector3i(10 + w, 18 + h, 28))).is_true()


func test_dig_box_mode_cycling() -> void:
	var ctrl := DigBoxController.new()
	auto_free(ctrl)

	assert_int(ctrl.mode).is_equal(DigBoxController.OrientationMode.HORIZONTAL)
	assert_str(ctrl.get_mode_name()).is_equal("Horizontal")

	ctrl.cycle_mode()
	assert_int(ctrl.mode).is_equal(DigBoxController.OrientationMode.VERTICAL)
	assert_str(ctrl.get_mode_name()).is_equal("Vertical")

	ctrl.cycle_mode()
	assert_int(ctrl.mode).is_equal(DigBoxController.OrientationMode.STAIRWAY_DOWN)
	assert_str(ctrl.get_mode_name()).is_equal("Stairway (Down)")
	assert_int(ctrl.width).is_equal(1)
	assert_int(ctrl.height).is_equal(3)

	ctrl.cycle_mode()
	assert_int(ctrl.mode).is_equal(DigBoxController.OrientationMode.HORIZONTAL)
	assert_str(ctrl.get_mode_name()).is_equal("Horizontal")


func test_dig_box_stairway_mesh_generation() -> void:
	var mesh := DigBoxController.build_stairway_mesh(3, Vector3i.FORWARD)
	assert_object(mesh).is_not_null()
	assert_int(mesh.get_surface_count()).is_greater(0)
