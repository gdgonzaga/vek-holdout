extends RefCounted
## Scratch Colony world for suites that exercise the producer/routing plumbing
## (farming, harvesting, crafting, jobs). Swaps Colony.storage_registry and
## Colony.job_board for test-owned instances and restores them afterwards —
## AGENTS.md: autoloads persist across suites, so swap-and-restore instead of
## mutating the real ones. Also hosts the shared actor/crate factories.
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
