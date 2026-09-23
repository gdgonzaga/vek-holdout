extends GdUnitTestSuite
## Colony backend: spawn, roster cap, ground-snap and serialization (ARCH
## "Subsystem: Colonists"). Moved out of suite_colony_management_test in R13 —
## these four tests never touch the ColonyManagement UI scene, only Colony
## itself, so they belong with the backend, not the panel.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

# Swap-and-restore (AGENTS.md): the sandbox swaps the registry, job board, map
# caches, and Colony's container (protects the spawn tests' on_map_wired calls;
# a dead container left by an earlier, non-sandboxed suite is normalized to null
# rather than crashing this suite's own restore).
var _sandbox: ColonySandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)


func after_test() -> void:
	_sandbox.restore()
	Colony.colonists.clear()
	# Spawn/deserialize tests leave squads, loadouts, areas and pending records behind; wipe them after the real registry and board are back.
	Colony.reset_for_new_game()


func test_spawn_colonist_success() -> void:
	var dummy_container: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(dummy_container)
	Colony.on_map_wired(dummy_container, [])

	var spawned: Colonist = Colony.spawn_colonist(null, Vector3(10, 0, 5))
	assert_object(spawned).is_not_null()
	assert_object(spawned.get_parent()).is_equal(dummy_container)
	assert_vector(spawned.global_position).is_equal(Vector3(10, 1, 5))
	assert_int(Colony.colonists.size()).is_equal(1)
	assert_object(Colony.colonists[0]).is_same(spawned)


## Marker Y is a hint: with a ground query wired (dual-voxel Phase 3), the
## spawn snaps XZ-preserving onto surface + epsilon; NAN keeps authored Y.
## Swap-and-restore — the query is autoload state.
func test_spawn_colonist_snaps_to_ground_query() -> void:
	var dummy_container: Node3D = auto_free(Node3D.new())
	add_child(dummy_container)
	Colony.on_map_wired(dummy_container, [])
	Colony.set_ground_query(func(_x: float, _z: float) -> float: return 5.0)
	var spawned: Colonist = Colony.spawn_colonist(null, Vector3(10, 0, 5))
	assert_object(spawned).is_not_null()
	assert_vector(spawned.global_position).is_equal(Vector3(10, 6.0, 5))
	Colony.set_ground_query(func(_x: float, _z: float) -> float: return NAN)
	var kept: Colonist = Colony.spawn_colonist(null, Vector3(0, 3, 0))
	assert_object(kept).is_not_null()
	assert_vector(kept.global_position).is_equal(Vector3(0, 4.0, 0))
	Colony.set_ground_query(Callable())


func test_spawn_colonist_cap_reached() -> void:
	var dummy_container: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(dummy_container)
	Colony.on_map_wired(dummy_container, [])

	for i in range(Colony.MVP_CAP):
		var c: Colonist = Colony.spawn_colonist(null, Vector3.ZERO)
		assert_object(c).is_not_null()

	var excess: Colonist = Colony.spawn_colonist(null, Vector3.ZERO)
	assert_object(excess).is_null()


func test_colony_serialize_deserialize_round_trip() -> void:
	var dummy_container: Node3D = auto_free(Node3D.new())
	add_child(dummy_container)
	Colony.on_map_wired(dummy_container, [])

	var spawned: Colonist = Colony.spawn_colonist(null, Vector3(5, 2, 8))
	assert_object(spawned).is_not_null()
	spawned.display_name = "Test Colonist"

	var serialized := Colony.serialize()
	assert_dict(serialized).contains_keys(["colonists"])
	var col_list: Array = serialized.get("colonists", [])
	assert_int(col_list.size()).is_equal(1)
	assert_str(col_list[0].get("display_name", "")).is_equal("Test Colonist")

	# Test reset_for_new_game
	Colony.reset_for_new_game()
	assert_int(Colony.colonists.size()).is_equal(0)

	# Test deserialize and map wiring
	Colony.deserialize(serialized)
	var new_container: Node3D = auto_free(Node3D.new())
	add_child(new_container)
	Colony.on_map_wired(new_container, [])

	assert_int(Colony.colonists.size()).is_equal(1)
	var restored: Colonist = Colony.colonists[0]
	assert_object(restored).is_not_null()
	assert_str(restored.display_name).is_equal("Test Colonist")
	assert_object(restored.get_parent()).is_equal(new_container)


# ── add_colonist (R13 candidate 1) ────────────────────────────────────────────

## No active map: the cap gate must still fire regardless of the container branch
## (nulling _container isolates that branch so a stale one from an earlier suite
## can't be dereferenced here).
func test_add_colonist_refuses_past_the_roster_cap() -> void:
	Colony._container = null
	var col_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	for i in range(Colony.MVP_CAP):
		var c: Colonist = auto_free(col_scene.instantiate() as Colonist)
		Colony.add_colonist(c)
	assert_int(Colony.colonists.size()).is_equal(Colony.MVP_CAP)

	var excess: Colonist = auto_free(col_scene.instantiate() as Colonist)
	Colony.add_colonist(excess)
	assert_int(Colony.colonists.size()).is_equal(Colony.MVP_CAP)
	assert_bool(Colony.colonists.has(excess)).is_false()


## An unparented colonist (never added to a scene tree, unlike sandbox.make_colonist's
## crates/colonists) gets parented under the wired map container and has the cached
## walkability predicate threaded into its own pathfinder.
func test_add_colonist_parents_and_wires_pathfinder_for_an_unparented_colonist() -> void:
	var dummy_container: Node3D = auto_free(Node3D.new())
	add_child(dummy_container)
	Colony.on_map_wired(dummy_container, [])
	Colony.set_walkability_predicate(func(cell: Vector3i) -> bool: return cell == Vector3i(3, 0, 3))

	var col_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var c: Colonist = auto_free(col_scene.instantiate() as Colonist)

	Colony.add_colonist(c)

	assert_object(c.get_parent()).is_same(dummy_container)
	assert_bool(c.pathfinder.is_walkable(Vector3i(3, 0, 3))).is_true()
	assert_bool(c.pathfinder.is_walkable(Vector3i(0, 0, 0))).is_false()


# ── remove_colonist (R13 candidate 2) ─────────────────────────────────────────
# Area membership cleanup is already pinned by
# suite_area_manager_test::test_colonist_removal_cleans_up_all_areas; these three
# cover the other effects, one per test, so a partial regression names which one broke.

func _make_roster_colonist() -> Colonist:
	var c := _sandbox.make_colonist()
	Colony.add_colonist(c)
	return c


func test_remove_colonist_clears_squad_membership() -> void:
	var c := _make_roster_colonist()
	Colony.assign_to_squad(c.colonist_id, "test_squad")
	assert_str(Colony.get_squad_for_colonist(c.colonist_id)).is_equal("test_squad")

	Colony.remove_colonist(c.colonist_id)

	assert_str(Colony.get_squad_for_colonist(c.colonist_id)).is_equal("")
	assert_bool(Colony.get_squad_members("test_squad").has(c.colonist_id)).is_false()
	Colony.squads.erase("test_squad")


func test_remove_colonist_cancels_active_deployment() -> void:
	var c := _make_roster_colonist()
	Colony.deploy_colonist(c.colonist_id, Vector3(9, 0, 9))
	assert_bool(Colony.has_active_deployment(c.colonist_id)).is_true()

	Colony.remove_colonist(c.colonist_id)

	assert_bool(Colony.has_active_deployment(c.colonist_id)).is_false()


func test_remove_colonist_drops_it_from_the_roster_and_detaches_the_node() -> void:
	var c := _make_roster_colonist()
	var cid := c.colonist_id
	assert_object(c.get_parent()).is_not_null()

	Colony.remove_colonist(cid)

	assert_object(Colony.get_colonist(cid)).is_null()
	assert_object(c.get_parent()).is_null()


# ── map-wiring setters re-point rostered pathfinders (R13 candidate 3) ───────
# VoxelPathfinder has no public getter for the stand-hint/cell-cost Callables it
# was handed (only the walkability predicate is publicly queryable, via
# is_walkable); reading the private mirror fields here matches the established
# convention ColonySandbox already uses for Colony's own private map caches.

func test_map_wiring_setters_repoint_every_rostered_colonists_pathfinder() -> void:
	var c1 := _make_roster_colonist()
	var c2 := _make_roster_colonist()

	var predicate := func(cell: Vector3i) -> bool: return cell == Vector3i(9, 9, 9)
	Colony.set_walkability_predicate(predicate)
	assert_bool(c1.pathfinder.is_walkable(Vector3i(9, 9, 9))).is_true()
	assert_bool(c2.pathfinder.is_walkable(Vector3i(9, 9, 9))).is_true()
	assert_bool(c1.pathfinder.is_walkable(Vector3i(0, 0, 0))).is_false()

	var hint := func(_x: float, _z: float) -> Vector3i: return Vector3i(1, 2, 3)
	Colony.set_stand_cell_hint(hint)
	assert_bool(c1.pathfinder._stand_cell_hint == hint).is_true()
	assert_bool(c2.pathfinder._stand_cell_hint == hint).is_true()

	var cost_fn := func(_cell: Vector3i) -> float: return 4.0
	Colony.set_cell_cost_fn(cost_fn)
	assert_bool(c1.pathfinder._cell_cost == cost_fn).is_true()
	assert_bool(c2.pathfinder._cell_cost == cost_fn).is_true()


# ── has_walkable_neighbor stand-hint branch (R13 candidate 4) ────────────────
# The direct-offset scan and the "no predicate bound" default are already pinned
# by suite_mining_test::test_dig_job_def_buried_job_gated_by_walkable_neighbor
# (verified with a mutant during this phase). Only the stand-cell-hint fallback
# — reached when none of the direct offsets are walkable — is unpinned.

func test_has_walkable_neighbor_checks_the_stand_cell_hint_when_direct_offsets_fail() -> void:
	var cell := Vector3i(5, 5, 5)
	# Diagonal in the XZ plane at the same Y: not one of Colony's _WORK_STAND_OFFSETS,
	# so only the stand-cell-hint's 3x3 column sweep can find it.
	var stand_cell := Vector3i(6, 5, 6)
	Colony.set_walkability_predicate(func(c: Vector3i) -> bool: return c == stand_cell)
	assert_bool(Colony.has_walkable_neighbor(cell)).is_false()

	Colony.set_stand_cell_hint(func(x: float, z: float) -> Vector3i:
		return stand_cell if int(x) == stand_cell.x and int(z) == stand_cell.z else Vector3i.MAX)
	assert_bool(Colony.has_walkable_neighbor(cell)).is_true()
