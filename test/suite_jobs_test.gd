extends GdUnitTestSuite

## Unit tests for the job foundations (ARCH "Subsystem: Colonists"): JobDef
## requirement gating enforced at selection + assignment, the MaterialSink
## duck-typed contract, hauling tool retention, and the Furniture state bag.

const HAULING_DEF: JobDef = preload("res://data/jobs/hauling.tres")
const COLONIST_SCENE: PackedScene = preload("res://subsystems/colonists/colonist.tscn")

# Swapped into Colony for haul tests so real map wiring isn't needed; restored
# in after_test (mutating the real registry's container would leak state).
var _real_registry: StorageRegistry
var _test_registry: StorageRegistry
var _container: Node3D


func before_test() -> void:
	_real_registry = Colony.storage_registry
	_test_registry = StorageRegistry.new()
	auto_free(_test_registry)
	_container = Node3D.new()
	auto_free(_container)
	_test_registry.on_map_wired(_container)
	Colony.storage_registry = _test_registry


func after_test() -> void:
	Colony.storage_registry = _real_registry


func _make_colonist() -> Colonist:
	var colonist: Colonist = COLONIST_SCENE.instantiate()
	add_child(auto_free(colonist))
	return colonist


func _false_leaf() -> NotCondition:
	var leaf: NotCondition = auto_free(NotCondition.new()) as NotCondition
	leaf.condition = Condition.new()
	return leaf


func _make_def(labor_id: String, conditions: Array) -> JobDef:
	var def: JobDef = auto_free(JobDef.new()) as JobDef
	def.id = labor_id
	def.display_name = labor_id
	def.labor_id = labor_id
	def.conditions.clear()
	for c in conditions:
		def.conditions.append(c)
	return def


## A crate Furniture (StorageInventory child, capacity set directly — the test
## bypasses def storage params; _ready's param read is a no-op without a def)
## registered in the test container. The container lives outside the tree, so
## nothing's _ready runs — everything needed is set here explicitly.
func _make_crate(planks: int) -> Furniture:
	var crate := Furniture.new()
	auto_free(crate)
	var storage := StorageInventory.new()
	storage.name = "StorageInventory"
	crate.add_child(storage)
	storage.capacity = 100.0
	storage.add("plank", planks)
	_container.add_child(crate)
	return crate


# ── Requirement gating ────────────────────────────────────────────────────────

func test_meets_requirements_empty_conditions_pass_with_null_target() -> void:
	var def := _make_def("construction", [])
	var job := Job.from_def(def)
	assert_bool(def.meets_requirements(null, job)).is_true()


func test_meets_requirements_failing_condition_fails() -> void:
	var def := _make_def("construction", [_false_leaf()])
	var job := Job.from_def(def)
	assert_bool(def.meets_requirements(null, job)).is_false()


func test_try_assign_enforces_requirements() -> void:
	var colonist := _make_colonist()
	var def := _make_def("construction", [_false_leaf()])
	var job := Job.from_def(def)
	assert_bool(job.try_assign(colonist)).is_false()
	assert_bool(job.is_assigned(colonist.colonist_id)).is_false()
	def.conditions.clear()
	assert_bool(job.try_assign(colonist)).is_true()
	job.unassign(colonist)


func test_get_best_job_for_skips_failing_requirements() -> void:
	var colonist := _make_colonist()
	colonist.set_labor_priority("construction", 2) # beats hauling's default 1
	var board := JobBoard.new()
	auto_free(board)
	var gated := Job.from_def(_make_def("construction", [_false_leaf()]))
	var open := Job.from_def(_make_def("hauling", []))
	board.add_job(gated)
	board.add_job(open)
	# The higher-priority gated job is filtered out; the open haul job wins.
	var best := board.get_best_job_for(colonist)
	assert_object(best).is_same(open)


func test_get_best_job_for_returns_null_when_all_gated() -> void:
	var colonist := _make_colonist()
	var board := JobBoard.new()
	auto_free(board)
	board.add_job(Job.from_def(_make_def("construction", [_false_leaf()])))
	assert_object(board.get_best_job_for(colonist)).is_null()


# ── MaterialSink contract ─────────────────────────────────────────────────────

func test_blueprint_is_a_material_sink() -> void:
	var bp: Blueprint = auto_free(Blueprint.new()) as Blueprint
	assert_bool(MaterialSink.is_material_sink(bp)).is_true()


func test_plain_nodes_are_not_material_sinks() -> void:
	assert_bool(MaterialSink.is_material_sink(null)).is_false()
	var plain: Node = auto_free(Node.new()) as Node
	assert_bool(MaterialSink.is_material_sink(plain)).is_false()
	var furniture := Furniture.new()
	auto_free(furniture)
	assert_bool(MaterialSink.is_material_sink(furniture)).is_false()


func test_hauling_fetches_for_any_material_sink() -> void:
	# The haul def talks to job.target_node through the four sink methods only —
	# a non-Blueprint sink must drive the same FETCH leg.
	var sink := FakeSink.new()
	auto_free(sink)
	add_child(sink)
	var crate := _make_crate(5)
	var job := Job.from_def(HAULING_DEF)
	job.target_node = sink
	job.location = Vector3.ZERO
	var leg := HAULING_DEF.get_next_leg(_make_colonist(), job)
	assert_int(leg.kind).is_equal(HaulingJobDef.FETCH)
	assert_object(leg.target_node).is_same(crate)


# ── Tool retention ────────────────────────────────────────────────────────────

func test_on_end_dumps_materials_but_keeps_tools() -> void:
	var colonist := _make_colonist()
	colonist.inventory.add("plank", 2)
	colonist.inventory.add("axe", 1) # data/items/axe.tres: tags ["tool", "axe"]
	var crate := _make_crate(0)
	var crate_inv := _test_registry.inventory_of(crate)
	HAULING_DEF.on_end(false, colonist, null, null, 0.0)
	assert_int(crate_inv.get_item_count("plank")).is_equal(2)
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(0)
	assert_int(colonist.inventory.get_item_count("axe")).is_equal(1)
	assert_int(crate_inv.get_item_count("axe")).is_equal(0)


func test_is_tool_reads_item_tags() -> void:
	assert_bool(HAULING_DEF._is_tool("axe")).is_true()
	assert_bool(HAULING_DEF._is_tool("plank")).is_false()
	assert_bool(HAULING_DEF._is_tool("nonexistent")).is_false()


# ── Furniture state bag ───────────────────────────────────────────────────────

func test_furniture_state_round_trip() -> void:
	var furniture := Furniture.new()
	auto_free(furniture)
	furniture.state = {"growable": {"stage": 2}}
	var data := furniture.serialize()
	assert_int(data["state"]["growable"]["stage"]).is_equal(2)
	var restored := Furniture.new()
	auto_free(restored)
	restored.deserialize(data)
	assert_int(restored.state["growable"]["stage"]).is_equal(2)


func test_furniture_deserialize_without_state_key() -> void:
	var furniture := Furniture.new()
	auto_free(furniture)
	furniture.deserialize({"def_id": "crate"})
	assert_bool(furniture.state.is_empty()).is_true()


# ── Test doubles ──────────────────────────────────────────────────────────────

## Minimal non-Blueprint MaterialSink: owes 3 planks forever (deposit_from is
## never exercised here — only the FETCH decision path reads it).
class FakeSink extends Node:
	func needed_item_ids() -> Array[String]:
		return ["plank"]

	func remaining_need(_item_id: String) -> int:
		return 3

	func deposit_from(_actor: Node) -> int:
		return 0

	func has_complete_materials() -> bool:
		return false
