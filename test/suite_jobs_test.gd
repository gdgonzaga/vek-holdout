extends GdUnitTestSuite

## Unit tests for the job foundations (ARCH "Subsystem: Colonists"): JobDef
## requirement gating enforced at selection + assignment, the MaterialSink
## duck-typed contract, hauling tool retention, and the Furniture state bag.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const JobFixtures = preload("res://test/helpers/job_fixtures.gd")
const ItemDbSandbox = preload("res://test/helpers/item_db_sandbox.gd")
const BuildLibrarySandbox = preload("res://test/helpers/build_library_sandbox.gd")

## Synthetic ids owned by this suite: the tests never depend on shipped items or blueprints.
const MATERIAL_ID := "test_plank"
const TOOL_ID := "test_axe"
const STATION_ID := "test_station"
const BLOCK_ID := "test_block"

var _sandbox: ColonySandbox
var _items: ItemDbSandbox
var _builds: BuildLibrarySandbox
var _hauling: HaulingJobDef
var _construction: ConstructionJobDef


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	_items = ItemDbSandbox.new(self)
	_builds = BuildLibrarySandbox.new(self)
	_hauling = JobFixtures.hauling()
	_construction = JobFixtures.construction()
	# A stackable material and a tool-tagged item: the two item kinds the hauling tests distinguish.
	_register_material_and_tool()


func after_test() -> void:
	_builds.restore()
	_items.restore()
	_sandbox.restore()


func _register_material_and_tool() -> void:
	var material: ItemDef = _items.add_item(MATERIAL_ID)
	material.weight = 0.1
	var tool_def: ItemDef = _items.add_item(TOOL_ID, "", [HaulingJobDef.TOOL_TAG])
	tool_def.weight = 0.5
	# Item id the moved def-lifecycle tests use for the hauled material.
	_items.add_item("plank")


## A 2x1x1 furniture buildable that costs 3 of MATERIAL_ID, registered in BuildLibrary.
func _make_station_def() -> FurnitureDef:
	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.id = STATION_ID
	def.display_name = "Test Station"
	def.dimensions = Vector3i(2, 1, 1)
	def.build_time = 4.0
	def.material_cost = [_make_cost(MATERIAL_ID, 3)]
	_builds.add_buildable(def)
	return def


## A costless one-cell block buildable, registered in BuildLibrary.
func _make_block_def() -> BlockDef:
	var def: BlockDef = auto_free(BlockDef.new())
	def.id = BLOCK_ID
	def.display_name = "Test Block"
	_builds.add_buildable(def)
	return def


func _make_cost(item_id: String, count: int) -> ItemAmount:
	var cost: ItemAmount = ItemAmount.new()
	cost.item_def = ItemDB.get_def(item_id)
	cost.count = count
	return cost


## A Blueprint of `def` parented under the sandbox container.
func _make_blueprint(def: BuildableDef, position: Vector3) -> Blueprint:
	var bp: Blueprint = auto_free(Blueprint.new()) as Blueprint
	bp.target_def_id = def.id
	bp.def = def
	_sandbox.container.add_child(bp)
	bp.global_position = position
	return bp


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
	_sandbox.make_crate(MATERIAL_ID, 0) # drought: no crate stocks a needed material
	var job := Job.from_def(_hauling)
	job.target_node = sink
	# Unclaimable while the drought lasts (selection skips it)…
	assert_bool(job.is_available()).is_false()
	# …but not dead: the job stays registered waiting for restock, and the
	# stalled run is not a completion.
	assert_bool(_hauling.should_close(job)).is_false()
	assert_bool(_hauling.job_complete(job)).is_false()


func test_restock_makes_drought_haul_job_claimable_again() -> void:
	var sink := FakeSink.new()
	auto_free(sink)
	add_child(sink)
	var crate := _sandbox.make_crate(MATERIAL_ID, 0)
	var job := Job.from_def(_hauling)
	job.target_node = sink
	_sandbox.test_registry.inventory_of(crate).add(MATERIAL_ID, 2)
	assert_bool(_hauling.is_available(job)).is_true()
	assert_bool(_hauling.should_close(job)).is_false()


func test_haul_job_closes_when_satisfied_or_sink_gone() -> void:
	var sink := FakeSink.new()
	auto_free(sink)
	add_child(sink)
	sink.satisfied = true
	var job := Job.from_def(_hauling)
	job.target_node = sink
	assert_bool(_hauling.should_close(job)).is_true()
	assert_bool(_hauling.job_complete(job)).is_true()
	job.target_node = null
	assert_bool(_hauling.should_close(job)).is_true()
	assert_bool(_hauling.job_complete(job)).is_false()


func test_default_def_should_close_mirrors_is_available() -> void:
	var def := _make_def("hauling", [])
	var job := Job.from_def(def)
	assert_bool(def.is_available(job)).is_true()
	assert_bool(def.should_close(job)).is_false()
	assert_bool(def.job_complete(job)).is_true()


func test_board_keeps_drought_haul_job_through_prune_until_restock() -> void:
	var colonist := _sandbox.make_colonist()
	var crate := _sandbox.make_crate(MATERIAL_ID, 0)
	var sink := FakeSink.new()
	auto_free(sink)
	add_child(sink)
	var board := JobBoard.new()
	auto_free(board)
	var job := Job.from_def(_hauling)
	job.target_node = sink
	job.location = Vector3.ZERO
	board.add_job(job)
	# Selection skips the drought job (the poll prunes first)…
	assert_object(board.get_best_job_for(colonist)).is_null()
	# …but the prune must not delete it — it waits on the board for restock.
	assert_object(board.get_job(job.id)).is_not_null()
	# A restocked crate flips it claimable; the next poll picks it up.
	_sandbox.test_registry.inventory_of(crate).add(MATERIAL_ID, 5)
	assert_object(board.get_best_job_for(colonist)).is_same(job)


func test_job_should_close_waits_for_last_assignee() -> void:
	var colonist := _sandbox.make_colonist()
	_sandbox.make_crate(MATERIAL_ID, 5)
	var sink := FakeSink.new()
	auto_free(sink)
	add_child(sink)
	var job := Job.from_def(_hauling)
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
	# without materials. The synthetic station costs MATERIAL_ID.
	var station := _make_station_def()
	var bp: Blueprint = auto_free(Blueprint.new()) as Blueprint
	bp.target_def_id = station.id
	_sandbox.make_crate(MATERIAL_ID, 0)
	var anchor := Vector3i(1, 2, 3)
	Colony._on_blueprint_placed(station.id, anchor, bp)
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
	Colony._on_blueprint_removed(station.id, anchor)
	assert_int(_sandbox.test_board.get_jobs().size()).is_equal(0)


# ── Tool retention ────────────────────────────────────────────────────────────

## The deliver cycle deposits up to the sink's need and retains the surplus in
## inventory for subsequent physical delivery — carried TOOLS are also kept.
func test_deliver_cycle_deposits_need_and_retains_surplus_and_tools() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.inventory.add(MATERIAL_ID, 5)  # 3 deposited, 2 surplus
	colonist.inventory.add(TOOL_ID, 1) # tagged as a tool (HaulingJobDef.TOOL_TAG)
	var crate := _sandbox.make_crate(MATERIAL_ID, 0)
	var crate_inv := _sandbox.test_registry.inventory_of(crate)
	var sink := SatisfyingFakeSink.new()
	auto_free(sink)
	add_child(sink)
	var job := Job.from_def(_hauling)
	job.target_node = sink
	_hauling.complete(colonist, job)
	assert_bool(sink.satisfied).is_true()
	assert_int(colonist.inventory.get_item_count(MATERIAL_ID)).is_equal(2)
	assert_int(crate_inv.get_item_count(MATERIAL_ID)).is_equal(0)
	assert_int(colonist.inventory.get_item_count(TOOL_ID)).is_equal(1)
	assert_int(crate_inv.get_item_count(TOOL_ID)).is_equal(0)


func test_is_tool_reads_item_tags() -> void:
	# Tags, not ids, decide toolness: a tool-tagged item with a plain name counts, an untagged
	# item whose name sounds like a tool does not.
	_items.add_item("test_wrench", "", [HaulingJobDef.TOOL_TAG])
	_items.add_item("test_untagged_axe")
	assert_bool(_hauling._is_tool("test_wrench")).is_true()
	assert_bool(_hauling._is_tool("test_untagged_axe")).is_false()
	assert_bool(_hauling._is_tool(TOOL_ID)).is_true()
	assert_bool(_hauling._is_tool(MATERIAL_ID)).is_false()
	assert_bool(_hauling._is_tool("nonexistent")).is_false()


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
	var bp := _make_blueprint(_make_station_def(), Vector3(2.5, 0.0, 2.5))
	var job := Job.from_def(_construction)
	job.target_node = bp
	
	assert_bool(_construction.is_available(job)).is_true()
	assert_bool(_construction.should_close(job)).is_false()
	
	var bystander := _sandbox.make_colonist()
	bystander.global_position = Vector3(2.0, 0.0, 2.0)
	Colony.colonists.append(bystander)
	
	assert_bool(_construction.is_available(job)).is_false()
	assert_bool(_construction.should_close(job)).is_false()
	
	bystander.global_position = Vector3(10.0, 0.0, 10.0)
	assert_bool(_construction.is_available(job)).is_true()
	
	Colony.colonists.erase(bystander)





func test_construction_gated_when_player_occupies_blueprint() -> void:
	var bp := _make_blueprint(_make_station_def(), Vector3(2.5, 0.0, 2.5))
	var job := Job.from_def(_construction)
	job.target_node = bp
	
	var player := _sandbox.make_player()
	player.global_position = Vector3(2.0, 0.0, 2.0)
	var old_player := SceneManager.get_player()
	SceneManager.set_player(player)
	
	assert_bool(_construction.is_available(job)).is_false()
	
	player.global_position = Vector3(10.0, 0.0, 10.0)
	assert_bool(_construction.is_available(job)).is_true()
	
	SceneManager.set_player(old_player)


func test_construction_gated_when_standing_inside_two_stacked_blueprints() -> void:
	# Blueprint 1 at Y=0 (lower block), Blueprint 2 at Y=1 (upper block)
	var block := _make_block_def()
	var bp1 := _make_blueprint(block, Vector3(2.0, 0.0, 2.0))
	bp1.anchor_cell = Vector3i(2, 0, 2)
	var bp2 := _make_blueprint(block, Vector3(2.0, 1.0, 2.0))
	bp2.anchor_cell = Vector3i(2, 1, 2)
	
	var job1 := Job.from_def(_construction)
	job1.target_node = bp1
	var job2 := Job.from_def(_construction)
	job2.target_node = bp2
	
	# Player standing at Y=0 (feet at Y=0, head at Y=1)
	var player := _sandbox.make_player()
	player.global_position = Vector3(2.0, 0.0, 2.0)
	var old_player := SceneManager.get_player()
	SceneManager.set_player(player)
	
	# BOTH stacked blueprints must be detected as occupied by the player
	assert_bool(_construction.is_available(job1)).is_false()
	assert_bool(_construction.is_available(job2)).is_false()
	
	# Player steps away to X=10
	player.global_position = Vector3(10.0, 0.0, 10.0)
	assert_bool(_construction.is_available(job1)).is_true()
	assert_bool(_construction.is_available(job2)).is_true()
	
	SceneManager.set_player(old_player)


## Carried unequipped tools in colonist pockets generate Store Carried Items and deposit into crates.
func test_store_carried_items_deposits_carried_tools_to_crate() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var crate: Furniture = _sandbox.make_crate(TOOL_ID, 0)
	var crate_inv: Inventory = _sandbox.test_registry.inventory_of(crate)
	crate.global_position = Vector3(5.0, 0.0, 5.0)

	colonist.inventory.add(TOOL_ID, 1)
	assert_int(colonist.inventory.get_item_count(TOOL_ID)).is_equal(1)

	var best_job: RefCounted = Colony.job_board.get_best_job_for(colonist)
	assert_object(best_job).is_not_null()
	assert_bool(best_job is Job).is_true()
	var haul_job: Job = best_job as Job
	assert_str(haul_job.title).is_equal("Store Carried Items")

	_hauling.complete(colonist, haul_job)
	assert_int(colonist.inventory.get_item_count(TOOL_ID)).is_equal(0)
	assert_int(crate_inv.get_item_count(TOOL_ID)).is_equal(1)


## Desired equipment in pockets is equipped immediately during audit rather than routed to crates.
func test_equipment_audit_equips_carried_tool_before_hygiene() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var crate: Furniture = _sandbox.make_crate(TOOL_ID, 0)
	var crate_inv: Inventory = _sandbox.test_registry.inventory_of(crate)
	crate.global_position = Vector3(5.0, 0.0, 5.0)

	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, TOOL_ID)
	colonist.inventory.add(TOOL_ID, 1)
	assert_int(colonist.inventory.get_item_count(TOOL_ID)).is_equal(1)
	assert_object(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND)).is_null()

	var job: RefCounted = Colony.job_board.get_best_job_for(colonist)
	assert_object(job).is_null()
	assert_object(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND)).is_not_null()
	assert_str(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal(TOOL_ID)
	assert_int(colonist.inventory.get_item_count(TOOL_ID)).is_equal(0)
	assert_int(crate_inv.get_item_count(TOOL_ID)).is_equal(0)


func test_is_available_for_accepts_already_assigned_colonist() -> void:
	var def := _make_def("construction", [])
	var job := Job.from_def(def)
	job.max_assignees = 1
	var colonist: Colonist = _sandbox.make_colonist()
	assert_bool(job.try_assign(colonist)).is_true()
	assert_int(job._assigned_colonists.size()).is_equal(1)
	assert_bool(job.is_available_for(colonist)).is_true()

	var other_colonist: Colonist = _sandbox.make_colonist()
	assert_bool(job.is_available_for(other_colonist)).is_false()


func test_construction_available_for_builder_at_blueprint() -> void:
	var bp := _make_blueprint(_make_station_def(), Vector3(2.0, 0.0, 2.0))
	var job := Job.from_def(_construction)
	job.target_node = bp

	var builder: Colonist = _sandbox.make_colonist()
	builder.global_position = Vector3(2.0, 0.0, 2.0)
	assert_bool(_construction.is_available_for(job, builder)).is_true()
	assert_bool(_construction.is_available(job)).is_false()


func test_world_item_haul_multileg_lifecycle() -> void:
	var crate := _sandbox.make_crate(MATERIAL_ID, 0)
	crate.global_position = Vector3(0, 0, 0)
	var crate_inv: Inventory = _sandbox.test_registry.inventory_of(crate)

	var ground_item: WorldItem = WorldItem.spawn_at(self, MATERIAL_ID, 4, Vector3(5, 0, 5))
	auto_free(ground_item)
	Colony.register_world_item(ground_item)

	var colonist: Colonist = _sandbox.make_colonist()
	colonist.global_position = Vector3(5, 0, 5)

	var job_ref: RefCounted = Colony.job_board.get_best_job_for(colonist)
	assert_object(job_ref).is_not_null()
	var job := job_ref as Job
	assert_bool(job.try_assign(colonist)).is_true()

	var bb := Blackboard.new()
	bb.set_var(&"active_job", job)

	# Leg 1: Pick up
	var claim_task := BTActionClaimJob.new()
	auto_free(claim_task)
	claim_task.initialize(colonist, bb, colonist)
	assert_int(claim_task.execute(0.1)).is_equal(BTAction.SUCCESS)
	assert_bool(bb.has_var(&"target_pos")).is_true()
	assert_vector(bb.get_var(&"target_pos")).is_equal_approx(Vector3(5, 0, 5), Vector3(0.1, 0.1, 0.1))

	var work_task := BTActionPerformWork.new()
	auto_free(work_task)
	work_task.initialize(colonist, bb, colonist)
	assert_int(work_task.execute(1.5)).is_equal(BTAction.SUCCESS)

	# After Leg 1, colonist carries the planks, but job is NOT released yet
	assert_int(colonist.inventory.get_item_count(MATERIAL_ID)).is_equal(4)
	assert_bool(bb.has_var(&"active_job")).is_true()
	assert_bool(job.is_assigned(colonist.colonist_id)).is_true()

	# Leg 2: Walk to crate
	colonist.global_position = Vector3(0, 0, 0)
	assert_int(claim_task.execute(0.1)).is_equal(BTAction.SUCCESS)
	assert_bool(bb.has_var(&"target_pos")).is_true()
	assert_vector(bb.get_var(&"target_pos")).is_equal_approx(Vector3(0, 0, 0), Vector3(0.1, 0.1, 0.1))

	# Leg 2: Deposit to crate
	assert_int(work_task.execute(1.5)).is_equal(BTAction.SUCCESS)
	assert_int(crate_inv.get_item_count(MATERIAL_ID)).is_equal(4)
	assert_int(colonist.inventory.get_item_count(MATERIAL_ID)).is_equal(0)
	assert_bool(bb.has_var(&"active_job")).is_false()
	assert_bool(job.is_assigned(colonist.colonist_id)).is_false()


func test_world_item_below_world_bounds_is_rejected() -> void:
	Colony.set_world_bounds(AABB(Vector3(-50, -10, -50), Vector3(100, 50, 100)))

	# Item below lowest point of the map (Y = -15 < -10)
	var void_item: WorldItem = WorldItem.spawn_at(self, MATERIAL_ID, 1, Vector3(0, -15, 0))
	auto_free(void_item)
	Colony.register_world_item(void_item)

	# Verify it was not registered on the job board
	assert_int(Colony.job_board.get_jobs().size()).is_equal(0)

	# Item within bounds (Y = -5 >= -10)
	var valid_item: WorldItem = WorldItem.spawn_at(self, MATERIAL_ID, 1, Vector3(0, -5, 0))
	auto_free(valid_item)
	Colony.register_world_item(valid_item)

	assert_int(Colony.job_board.get_jobs().size()).is_equal(1)


## Regression (blueprint never finishes): ConstructionJobDef.complete must
## materialize the blueprint and drop the job from the board. Before the def
## contract existed, PerformWork had no effect path for construction and
## colonists looped at the blueprint forever.
func test_construction_def_completes_blueprint_and_drops_job() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var bp: Blueprint = auto_free(Blueprint.new()) as Blueprint
	_sandbox.container.add_child(bp)
	var layer := StubBlueprintLayer.new()
	bp.layer = layer

	var job := Job.from_def(_construction)
	job.target_node = bp
	Colony.job_board.add_job(job)

	_construction.complete(colonist, job)
	assert_int(layer.completed.size()).is_equal(1)
	assert_object(layer.completed[0]).is_same(bp)
	assert_object(Colony.job_board.get_job(job.id)).is_null()


## An occupied blueprint (someone standing in its volume) hides the job and
## blocks complete() — the job waits on the board instead of entombing them.
func test_construction_def_holds_job_while_blueprint_occupied() -> void:
	var builder: Colonist = _sandbox.make_colonist()
	var occupant: Colonist = _sandbox.make_colonist()
	var bp: Blueprint = auto_free(Blueprint.new()) as Blueprint
	_sandbox.container.add_child(bp)
	occupant.global_position = Vector3(0.5, 0.0, 0.5)  # inside cell (0,0,0)
	var layer := StubBlueprintLayer.new()
	bp.layer = layer

	var job := Job.from_def(_construction)
	job.target_node = bp
	Colony.job_board.add_job(job)

	assert_bool(_construction.is_available(job)).is_false()
	_construction.complete(builder, job)
	assert_int(layer.completed.size()).is_equal(0)
	assert_object(Colony.job_board.get_job(job.id)).is_not_null()


## The base JobDef contract's default terminal effect: drop the job from the
## board so ClaimJob claims fresh work next tick.
func test_base_def_complete_drops_job_from_board() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var def: JobDef = auto_free(JobDef.new()) as JobDef
	def.labor_id = "hauling"  # unmapped labor: skill recording is a no-op
	var job := Job.from_def(def)
	Colony.job_board.add_job(job)

	def.complete(colonist, job)
	assert_object(Colony.job_board.get_job(job.id)).is_null()


## Hauling picks its walk target from carry state: the stocking crate while
## empty-handed, the sink while carrying a still-needed material.
func test_hauling_def_picks_work_site_by_carry_state() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var crate: Furniture = _sandbox.make_crate("plank", 5)
	crate.global_position = Vector3(10.0, 0.0, 10.0)
	var sink := FakeMaterialSink.new()
	auto_free(sink)
	_sandbox.container.add_child(sink)

	var job := Job.from_def(_hauling)
	job.target_node = sink
	job.location = Vector3(3.0, 0.0, 3.0)
	Colony.job_board.add_job(job)

	assert_bool(_hauling.is_available(job)).is_true()
	assert_vector(_hauling.work_site(colonist, job) as Vector3).is_equal(Vector3(10.0, 0.0, 10.0))

	colonist.inventory.add("plank", 2)
	assert_vector(_hauling.work_site(colonist, job) as Vector3).is_equal(Vector3(3.0, 0.0, 3.0))


## One full hauling run through the def's fetch/deliver cycles: withdraw up to
## the sink's need from the crate, then deposit into the sink — the job ends by
## satisfaction (should_close), never by a terminal complete.
func test_hauling_def_complete_fetches_then_delivers() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var crate: Furniture = _sandbox.make_crate("plank", 5)
	crate.global_position = Vector3(10.0, 0.0, 10.0)
	var sink := FakeMaterialSink.new()
	auto_free(sink)
	_sandbox.container.add_child(sink)

	var job := Job.from_def(_hauling)
	job.target_node = sink
	job.location = Vector3(3.0, 0.0, 3.0)

	_hauling.complete(colonist, job)  # FETCH
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(3)
	assert_int(_sandbox.test_registry.inventory_of(crate).get_item_count("plank")).is_equal(2)

	_hauling.complete(colonist, job)  # DELIVER
	assert_int(sink.deposited).is_equal(3)
	assert_bool(sink.satisfied).is_true()
	assert_bool(_hauling.job_complete(job)).is_true()
	assert_bool(_hauling.should_close(job)).is_true()


## Hauling picks work_site correctly for fractional JobInstance when carrying material.
func test_hauling_def_work_site_with_job_instance() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var crate: Furniture = _sandbox.make_crate("plank", 5)
	crate.global_position = Vector3(10.0, 0.0, 10.0)
	var sink := FakeMaterialSink.new()
	auto_free(sink)
	_sandbox.container.add_child(sink)

	var job_inst := JobInstance.create_haul(
		_hauling,
		&"plank",
		3,
		Vector3(10.0, 0.0, 10.0),
		Vector3(4.0, 0.0, 4.0),
		sink
	)
	Colony.job_board.add_job(job_inst)

	assert_vector(_hauling.work_site(colonist, job_inst) as Vector3).is_equal(Vector3(10.0, 0.0, 10.0))

	colonist.inventory.add("plank", 2)
	assert_vector(_hauling.work_site(colonist, job_inst) as Vector3).is_equal(Vector3(4.0, 0.0, 4.0))


## When the sink becomes satisfied before hauler arrives, complete() does not deposit surplus to crate (retains it).
func test_hauling_def_retains_surplus_when_sink_satisfied_early() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var crate: Furniture = _sandbox.make_crate("plank", 0)
	crate.global_position = Vector3(10.0, 0.0, 10.0)
	var sink := FakeMaterialSink.new()
	sink.satisfied = true
	auto_free(sink)
	_sandbox.container.add_child(sink)

	var job := Job.from_def(_hauling)
	job.target_node = sink
	job.location = Vector3(3.0, 0.0, 3.0)

	colonist.inventory.add("plank", 3)
	_hauling.complete(colonist, job)
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(3)
	assert_int(_sandbox.test_registry.inventory_of(crate).get_item_count("plank")).is_equal(0)


# ── Test doubles ──────────────────────────────────────────────────────────────

## Minimal non-Blueprint MaterialSink: owes 3 planks until `satisfied` flips
## (deposit_from is never exercised here — only the FETCH decision path and the
## lifetime gates read it).
class FakeSink extends Node:
	var satisfied := false

	func needed_item_ids() -> Array[String]:
		return [MATERIAL_ID]

	func remaining_need(_item_id: String) -> int:
		return 3

	func deposit_from(_actor: Node) -> int:
		return 0

	func has_complete_materials() -> bool:
		return satisfied


## FakeSink that actually withdraws on deposit_from (the Blueprint.deposit_from
## behavior) and flips satisfied on the first deposit — for exercising the
## hauling def's full DELIVER cycle.
class SatisfyingFakeSink extends FakeSink:
	func deposit_from(actor: Node) -> int:
		var need: int = remaining_need(MATERIAL_ID)
		var short: int = actor.remove_item(MATERIAL_ID, need)
		var taken: int = need - short
		if taken > 0:
			satisfied = true
		return taken


## Records BlueprintLayer.complete_blueprint calls without touching the voxel
## world (construction def tests).
class StubBlueprintLayer extends RefCounted:
	var completed: Array = []

	func complete_blueprint(bp: Blueprint, _builder: Node) -> bool:
		completed.append(bp)
		return true


## MaterialSink duck-type for hauling def tests (the suite_jobs FakeSink
## pattern, plus a real withdraw on deposit_from).
class FakeMaterialSink extends Node:
	var satisfied := false
	var deposited := 0

	func needed_item_ids() -> Array[String]:
		var out: Array[String] = []
		if not satisfied:
			out.append("plank")
		return out

	func remaining_need(_item_id: String) -> int:
		return 0 if satisfied else 3

	func has_complete_materials() -> bool:
		return satisfied

	func deposit_from(actor: Node) -> int:
		var need: int = remaining_need("plank")
		var short: int = actor.remove_item("plank", need)
		var taken: int = need - short
		deposited += taken
		if taken > 0:
			satisfied = true
		return taken
