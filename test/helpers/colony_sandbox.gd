extends RefCounted
## Scratch Colony world for suites that exercise the producer/routing plumbing
## (farming, harvesting, crafting, jobs). Swaps Colony.storage_registry and
## Colony.job_board for test-owned instances and restores them afterwards —
## AGENTS.md: autoloads persist across suites, so swap-and-restore instead of
## mutating the real ones. Also isolates the map-wiring caches (walkability, stand
## hint, cell cost, ground query, terrain predicate, world bounds, and the active
## map's colonist container): a sandbox starts with them unbound and restore() puts
## back whatever an earlier suite left there (a dead container reference is
## normalized to null instead of being carried forward). Also hosts the shared
## actor/crate factories.
##
## Composition on purpose: extending GdUnitTestSuite would make the gdUnit
## scanner pick this file up as an (empty) suite, and a RefCounted helper keeps
## every suite's before_test/after_test explicit about the swap.
##
## Usage:
##   var _sandbox := ColonySandbox.new(self)  # in before_test
##   _sandbox.restore()                       # in after_test

const COLONIST_SCENE: PackedScene = preload("res://subsystems/colonists/colonist.tscn")
const PLAYER_SCENE: PackedScene = preload("res://subsystems/player/player.tscn")

var _suite: GdUnitTestSuite
var _real_registry: StorageRegistry
var _real_board: JobBoard
var _real_walkability: Callable
var _real_stand_hint: Callable
var _real_cell_cost: Callable
var _real_ground_query: Callable
var _real_terrain_predicate: Callable
var _real_world_bounds: AABB
var _real_container: Node3D

## The swapped-in, test-owned registry/board (auto-freed with the suite).
var test_registry: StorageRegistry
var test_board: JobBoard

## Fresh per-test container, in-tree so spawned furniture _ready runs
## (capability params load). Wire FurnitureLayers to it via set_container.
var container: Node3D


func _init(suite: GdUnitTestSuite) -> void:
	_suite = suite
	_real_registry = Colony.storage_registry
	_real_board = Colony.job_board
	# Map-wiring caches: remember what an earlier suite may have left on Colony, then start this test from the unbound defaults so its job gating cannot depend on that.
	_snapshot_and_reset_map_caches()
	test_registry = StorageRegistry.new()
	test_board = JobBoard.new()
	container = Node3D.new()
	_suite.auto_free(test_registry)
	_suite.auto_free(test_board)
	_suite.auto_free(container)
	_suite.add_child(container)
	test_registry.on_map_wired(container)
	Colony.storage_registry = test_registry
	Colony.job_board = test_board


func restore() -> void:
	Colony.storage_registry = _real_registry
	Colony.job_board = _real_board
	# Map-wiring caches: put the pre-test values back through the setters so live colonists and the scratch pathfinder are re-pointed too.
	_restore_map_caches()


func _snapshot_and_reset_map_caches() -> void:
	## Auxiliary: Colony keeps the active map's predicates as private Callables with no
	## getters; copy them, then unbind so a sandbox test starts from the "no map" defaults.
	_real_walkability = Colony._walkability_predicate
	_real_stand_hint = Colony._stand_cell_hint
	_real_cell_cost = Colony._cell_cost_fn
	_real_ground_query = Colony._ground_query
	_real_terrain_predicate = Colony._is_terrain_at
	_real_world_bounds = Colony.get_world_bounds()
	# Colony._container is a plain Node3D reference with no restoring owner before this
	# sandbox existed: an earlier, non-sandboxed suite can leave it pointing at a node
	# that node's own suite already freed. Round-tripping a freed reference through
	# restore() later would itself throw ("previously freed"), so a dead reference is
	# normalized to null here rather than carried forward to the next sandboxed suite.
	_real_container = Colony._container if is_instance_valid(Colony._container) else null
	Colony.set_walkability_predicate(Callable())
	Colony.set_stand_cell_hint(Callable())
	Colony.set_cell_cost_fn(Callable())
	Colony.set_ground_query(Callable())
	Colony.set_terrain_predicate(Callable())
	Colony.set_world_bounds(AABB())
	Colony._container = null


func _restore_map_caches() -> void:
	## Auxiliary: inverse of _snapshot_and_reset_map_caches; safe to call repeatedly.
	Colony.set_walkability_predicate(_real_walkability)
	Colony.set_stand_cell_hint(_real_stand_hint)
	Colony.set_cell_cost_fn(_real_cell_cost)
	Colony.set_ground_query(_real_ground_query)
	Colony.set_terrain_predicate(_real_terrain_predicate)
	Colony.set_world_bounds(_real_world_bounds)
	# _real_container was already normalized to null in _snapshot_and_reset_map_caches
	# if it was a dead reference, so this assignment can never throw.
	Colony._container = _real_container


func make_colonist() -> Colonist:
	var c: Colonist = COLONIST_SCENE.instantiate()
	_suite.auto_free(c)
	container.add_child(c)
	return c


func make_player() -> Player:
	var p: Player = PLAYER_SCENE.instantiate()
	_suite.auto_free(p)
	container.add_child(p)
	return p


## A crate Furniture (StorageInventory child, capacity 100) stocked with
## `count` of `item_id`, parented under the sandbox container.
func make_crate(item_id: String, count: int) -> Furniture:
	var crate := Furniture.new()
	_suite.auto_free(crate)
	var storage := StorageInventory.new()
	storage.name = "StorageInventory"
	storage.capacity = 100.0
	storage.add(item_id, count)
	crate.add_child(storage)
	container.add_child(crate)
	return crate


## Raw skill-use counter for the single-XP-site regression checks
## (ARCH Skills: defs must never record uses themselves).
func skill_uses(skill_set: SkillSet, skill_id: String) -> int:
	return int(skill_set.skills.get(skill_id, {}).get("progress", 0))
