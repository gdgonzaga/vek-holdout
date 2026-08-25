extends GdUnitTestSuite

## Unit tests for the job foundations (ARCH "Subsystem: Colonists"): JobDef
## requirement gating enforced at selection + assignment, the MaterialSink
## duck-typed contract, hauling tool retention, and the Furniture state bag.

const HAULING_DEF: JobDef = preload("res://data/jobs/hauling.tres")
const CONSTRUCTION_DEF: JobDef = preload("res://data/jobs/construction.tres")

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

var _sandbox: ColonySandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)


func after_test() -> void:
	_sandbox.restore()


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
	var colonist := _sandbox.make_colonist()
	var def := _make_def("construction", [_false_leaf()])
	var job := Job.from_def(def)
	assert_bool(job.try_assign(colonist)).is_false()
	assert_bool(job.is_assigned(colonist.colonist_id)).is_false()
	def.conditions.clear()
	assert_bool(job.try_assign(colonist)).is_true()
	job.unassign(colonist)


func test_get_best_job_for_skips_failing_requirements() -> void:
	var colonist := _sandbox.make_colonist()
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
	var colonist := _sandbox.make_colonist()
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





# ── Drought persistence (job lifetime vs claimability) ────────────────────────

func test_haul_job_survives_source_drought() -> void:
	var sink := FakeSink.new()
	auto_free(sink)
	add_child(sink)
	_sandbox.make_crate("plank", 0) # drought: no crate stocks a needed material
	var job := Job.from_def(HAULING_DEF)
	job.target_node = sink
	# Unclaimable while the drought lasts (selection skips it)…
	assert_bool(job.is_available()).is_false()
	# …but not dead: the job stays registered waiting for restock, and the
	# stalled run is not a completion.
	assert_bool(HAULING_DEF.should_close(job)).is_false()
	assert_bool(HAULING_DEF.job_complete(job)).is_false()


func test_restock_makes_drought_haul_job_claimable_again() -> void:
	var sink := FakeSink.new()
	auto_free(sink)
	add_child(sink)
	var crate := _sandbox.make_crate("plank", 0)
	var job := Job.from_def(HAULING_DEF)
	job.target_node = sink
	_sandbox.test_registry.inventory_of(crate).add("plank", 2)
	assert_bool(HAULING_DEF.is_available(job)).is_true()
	assert_bool(HAULING_DEF.should_close(job)).is_false()


func test_haul_job_closes_when_satisfied_or_sink_gone() -> void:
	var sink := FakeSink.new()
	auto_free(sink)
	add_child(sink)
	sink.satisfied = true
	var job := Job.from_def(HAULING_DEF)
	job.target_node = sink
	assert_bool(HAULING_DEF.should_close(job)).is_true()
	assert_bool(HAULING_DEF.job_complete(job)).is_true()
	job.target_node = null
	assert_bool(HAULING_DEF.should_close(job)).is_true()
	assert_bool(HAULING_DEF.job_complete(job)).is_false()


func test_default_def_should_close_mirrors_is_available() -> void:
	var def := _make_def("hauling", [])
	var job := Job.from_def(def)
	assert_bool(def.is_available(job)).is_true()
	assert_bool(def.should_close(job)).is_false()
	assert_bool(def.job_complete(job)).is_true()


func test_board_keeps_drought_haul_job_through_prune_until_restock() -> void:
	var colonist := _sandbox.make_colonist()
	var crate := _sandbox.make_crate("plank", 0)
	var sink := FakeSink.new()
	auto_free(sink)
	add_child(sink)
	var board := JobBoard.new()
	auto_free(board)
	var job := Job.from_def(HAULING_DEF)
	job.target_node = sink
	job.location = Vector3.ZERO
	board.add_job(job)
	# Selection skips the drought job (the poll prunes first)…
	assert_object(board.get_best_job_for(colonist)).is_null()
	# …but the prune must not delete it — it waits on the board for restock.
	assert_object(board.get_job(job.id)).is_not_null()
	# A restocked crate flips it claimable; the next poll picks it up.
	_sandbox.test_registry.inventory_of(crate).add("plank", 5)
	assert_object(board.get_best_job_for(colonist)).is_same(job)


func test_job_should_close_waits_for_last_assignee() -> void:
	var colonist := _sandbox.make_colonist()
	_sandbox.make_crate("plank", 5)
	var sink := FakeSink.new()
	auto_free(sink)
	add_child(sink)
	var job := Job.from_def(HAULING_DEF)
	job.target_node = sink
	assert_bool(job.try_assign(colonist)).is_true()
	# The sink satisfies mid-run (a parallel hauler's DELIVER crossed it).
	sink.satisfied = true
	assert_bool(job.should_close()).is_false() # assignee still draining
	job.unassign(colonist)
	assert_bool(job.should_close()).is_true()


# ── Producer decision ─────────────────────────────────────────────────────────

func test_producer_spawns_haul_job_with_zero_stock() -> void:
	# A material'd blueprint spawns a haul job even when NO crate stocks the
	# needed material — the job drought-waits on the board instead of building
	# without materials. workbench costs 15 planks (data/furniture/workbench.tres).
	var bp: Blueprint = auto_free(Blueprint.new()) as Blueprint
	bp.target_def_id = "workbench"
	_sandbox.make_crate("plank", 0)
	var anchor := Vector3i(1, 2, 3)
	Colony._on_blueprint_placed("workbench", anchor, bp)
	var spawned: Job = null
	for j in _sandbox.test_board.get_jobs():
		if j.anchor_cell == anchor:
			spawned = j
			break
	assert_object(spawned).is_not_null()
	assert_str(spawned.labor_id).is_equal("hauling")
	assert_bool(spawned.should_close()).is_false() # drought-waiting, not dead
	# Removal drops jobs by anchor — a later blueprint_removed can never strand
	# one on the board.
	Colony._on_blueprint_removed("workbench", anchor)
	assert_int(_sandbox.test_board.get_jobs().size()).is_equal(0)


# ── Tool retention ────────────────────────────────────────────────────────────

func test_on_end_dumps_materials_but_keeps_tools() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.inventory.add("plank", 2)
	colonist.inventory.add("axe", 1) # data/items/axe.tres: tags ["tool", "axe"]
	var crate := _sandbox.make_crate("plank", 0)
	var crate_inv := _sandbox.test_registry.inventory_of(crate)
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


# ── Failure & Cooldown ────────────────────────────────────────────────────────

func test_job_failure_cooldown_and_backoff() -> void:
	var board := JobBoard.new()
	auto_free(board)
	var job := Job.new()
	board.add_job(job)
	
	for i in range(3):
		board.fail(job.id, "unreachable")
	assert_bool(job.is_available()).is_true()
	
	board.fail(job.id, "unreachable")
	assert_bool(job.is_available()).is_false()
	assert_int(job.sleep_until_msec).is_greater(Time.get_ticks_msec())
	
	job.sleep_until_msec = 0
	job.failure_count = 5
	board.fail(job.id, "unreachable")
	assert_bool(job.is_available()).is_false()
	assert_int(job.sleep_until_msec - Time.get_ticks_msec()).is_greater(55000)
	
	job.failure_count = 9
	board.fail(job.id, "unreachable")
	assert_bool(job.is_available()).is_false()
	assert_int(job.sleep_until_msec - Time.get_ticks_msec()).is_greater(295000)


func test_world_changed_wakes_sleeping_jobs() -> void:
	var board := JobBoard.new()
	auto_free(board)
	var job := Job.new()
	job.sleep_until_msec = Time.get_ticks_msec() + 60000
	board.add_job(job)
	
	assert_bool(job.is_available()).is_false()
	board._on_world_changed()
	assert_bool(job.is_available()).is_true()
	assert_int(job.sleep_until_msec).is_equal(0)


# ── Construction occupation & stacked blueprints ──────────────────────────────

func test_construction_is_available_when_clear_and_gated_when_occupied() -> void:
	var bp: Blueprint = auto_free(Blueprint.new()) as Blueprint
	bp.target_def_id = "workbench"
	bp.def = BuildLibrary.get_def("workbench")
	_sandbox.container.add_child(bp)
	bp.global_position = Vector3(2.5, 0.0, 2.5)
	var job := Job.from_def(CONSTRUCTION_DEF)
	job.target_node = bp
	
	assert_bool(CONSTRUCTION_DEF.is_available(job)).is_true()
	assert_bool(CONSTRUCTION_DEF.should_close(job)).is_false()
	
	var bystander := _sandbox.make_colonist()
	bystander.global_position = Vector3(2.0, 0.0, 2.0)
	Colony.colonists.append(bystander)
	
	assert_bool(CONSTRUCTION_DEF.is_available(job)).is_false()
	assert_bool(CONSTRUCTION_DEF.should_close(job)).is_false()
	
	bystander.global_position = Vector3(10.0, 0.0, 10.0)
	assert_bool(CONSTRUCTION_DEF.is_available(job)).is_true()
	
	Colony.colonists.erase(bystander)





func test_construction_gated_when_player_occupies_blueprint() -> void:
	var bp: Blueprint = auto_free(Blueprint.new()) as Blueprint
	bp.target_def_id = "workbench"
	bp.def = BuildLibrary.get_def("workbench")
	_sandbox.container.add_child(bp)
	bp.global_position = Vector3(2.5, 0.0, 2.5)
	var job := Job.from_def(CONSTRUCTION_DEF)
	job.target_node = bp
	
	var player := _sandbox.make_player()
	player.global_position = Vector3(2.0, 0.0, 2.0)
	var old_player := SceneManager.get_player()
	SceneManager.set_player(player)
	
	assert_bool(CONSTRUCTION_DEF.is_available(job)).is_false()
	
	player.global_position = Vector3(10.0, 0.0, 10.0)
	assert_bool(CONSTRUCTION_DEF.is_available(job)).is_true()
	
	SceneManager.set_player(old_player)


func test_construction_gated_when_standing_inside_two_stacked_blueprints() -> void:
	# Blueprint 1 at Y=0 (lower block), Blueprint 2 at Y=1 (upper block)
	var bp1: Blueprint = auto_free(Blueprint.new()) as Blueprint
	bp1.target_def_id = "wood"
	bp1.def = BuildLibrary.get_def("wood")
	bp1.anchor_cell = Vector3i(2, 0, 2)
	_sandbox.container.add_child(bp1)
	bp1.global_position = Vector3(2.0, 0.0, 2.0)
	
	var bp2: Blueprint = auto_free(Blueprint.new()) as Blueprint
	bp2.target_def_id = "wood"
	bp2.def = BuildLibrary.get_def("wood")
	bp2.anchor_cell = Vector3i(2, 1, 2)
	_sandbox.container.add_child(bp2)
	bp2.global_position = Vector3(2.0, 1.0, 2.0)
	
	var job1 := Job.from_def(CONSTRUCTION_DEF)
	job1.target_node = bp1
	var job2 := Job.from_def(CONSTRUCTION_DEF)
	job2.target_node = bp2
	
	# Player standing at Y=0 (feet at Y=0, head at Y=1)
	var player := _sandbox.make_player()
	player.global_position = Vector3(2.0, 0.0, 2.0)
	var old_player := SceneManager.get_player()
	SceneManager.set_player(player)
	
	# BOTH stacked blueprints must be detected as occupied by the player
	assert_bool(CONSTRUCTION_DEF.is_available(job1)).is_false()
	assert_bool(CONSTRUCTION_DEF.is_available(job2)).is_false()
	
	# Player steps away to X=10
	player.global_position = Vector3(10.0, 0.0, 10.0)
	assert_bool(CONSTRUCTION_DEF.is_available(job1)).is_true()
	assert_bool(CONSTRUCTION_DEF.is_available(job2)).is_true()
	
	SceneManager.set_player(old_player)


# ── Test doubles ──────────────────────────────────────────────────────────────

## Minimal non-Blueprint MaterialSink: owes 3 planks until `satisfied` flips
## (deposit_from is never exercised here — only the FETCH decision path and the
## lifetime gates read it).
class FakeSink extends Node:
	var satisfied := false

	func needed_item_ids() -> Array[String]:
		return ["plank"]

	func remaining_need(_item_id: String) -> int:
		return 3

	func deposit_from(_actor: Node) -> int:
		return 0

	func has_complete_materials() -> bool:
		return satisfied
