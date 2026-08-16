extends GdUnitTestSuite

## Unit tests for the crafting feature (ARCH "Subsystem: Crafting",
## job-extensions.md "Crafting"): the CraftingStation component as a
## MaterialSink (order ledger + deposit crossing), CraftingJobDef (begin/
## complete/gates), the Colony routing (queue → haul, materials-ready → craft),
## FurnitureLayer attachment, and persistence through the Furniture state bag.

const CRAFTING_DEF: JobDef = preload("res://data/jobs/crafting.tres")
const HAULING_DEF: JobDef = preload("res://data/jobs/hauling.tres")
const COLONIST_SCENE: PackedScene = preload("res://subsystems/colonists/colonist.tscn")
const PLAYER_SCENE: PackedScene = preload("res://subsystems/player/player.tscn")
const WORKBENCH_DEF: FurnitureDef = preload("res://data/furniture/workbench.tres")

# Swapped into Colony for the run so producers (signal-driven or direct) write
# to a scratch board/registry; restored in after_test.
var _real_registry: StorageRegistry
var _real_board: JobBoard
var _test_registry: StorageRegistry
var _test_board: JobBoard
var _container: Node3D


func before_test() -> void:
	_real_registry = Colony.storage_registry
	_real_board = Colony.job_board
	_test_registry = StorageRegistry.new()
	auto_free(_test_registry)
	_test_board = JobBoard.new()
	auto_free(_test_board)
	_container = Node3D.new()
	auto_free(_container)
	add_child(_container) # in-tree so spawned furniture _ready runs (params load)
	_test_registry.on_map_wired(_container)
	Colony.storage_registry = _test_registry
	Colony.job_board = _test_board


func after_test() -> void:
	Colony.storage_registry = _real_registry
	Colony.job_board = _real_board


func _make_colonist() -> Colonist:
	var colonist: Colonist = COLONIST_SCENE.instantiate()
	add_child(auto_free(colonist))
	return colonist


func _make_player() -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(auto_free(player))
	return player


## A station-capable Furniture (CraftingStation child, recipes set directly —
## the _make_crate pattern: container out-of-tree, so nothing's _ready runs
## and the caller owns the wiring).
func _make_station(recipes: Array) -> CraftingStation:
	var furniture := Furniture.new()
	auto_free(furniture)
	var station := CraftingStation.new()
	station.name = "CraftingStation"
	furniture.add_child(station)
	for r in recipes:
		station.recipes.append(r)
	_container.add_child(furniture)
	return station


## Flat-pair convenience: _amounts(["plank", 2, "wood_block", 1]).
func _amounts(flat: Array) -> Array[ItemAmount]:
	var out: Array[ItemAmount] = []
	for i in range(0, flat.size(), 2):
		var amount: ItemAmount = auto_free(ItemAmount.new()) as ItemAmount
		amount.item_def = ItemDB.get_def(flat[i])
		amount.count = flat[i + 1]
		out.append(amount)
	return out


func _recipe(id: String, inputs: Array, outputs: Array, base_time: float,
		conditions: Array = []) -> RecipeDef:
	var recipe: RecipeDef = auto_free(RecipeDef.new()) as RecipeDef
	recipe.id = id
	recipe.display_name = id
	recipe.inputs = _amounts(inputs)
	recipe.outputs = _amounts(outputs)
	recipe.base_time = base_time
	for c in conditions:
		recipe.conditions.append(c)
	return recipe


func _make_crate(item_id: String, count: int) -> Furniture:
	var crate := Furniture.new()
	auto_free(crate)
	var storage := StorageInventory.new()
	storage.name = "StorageInventory"
	crate.add_child(storage)
	storage.capacity = 100.0
	storage.add(item_id, count)
	_container.add_child(crate)
	return crate


func _gate(min_level: int) -> MinSkillCondition:
	var gate: MinSkillCondition = auto_free(MinSkillCondition.new()) as MinSkillCondition
	gate.skill_id = "crafting"
	gate.min_level = min_level
	return gate


## Counts EventBus emissions between construction and read() (disconnects).
class SignalCounter extends RefCounted:
	var count := 0
	var _callable: Callable
	var _signal: Signal

	func _init(signal_ref: Signal) -> void:
		_signal = signal_ref
		_callable = Callable(self, "_on_signal")
		_signal.connect(_callable)

	func _on_signal(_a = null, _b = null) -> void:
		count += 1

	func read() -> int:
		_signal.disconnect(_callable)
		return count


# ── CraftingStation as a MaterialSink ─────────────────────────────────────────

func test_station_is_a_material_sink() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	assert_bool(MaterialSink.is_material_sink(station)).is_true()


func test_no_order_station_reads_satisfied_to_hauling() -> void:
	# Vacuous satisfied: no needs + has_complete_materials true. A haul job
	# bound to an orderless station closes through HaulingJobDef's normal
	# lifecycle — the semantics that avoid immortal dead jobs.
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	assert_bool(station.needed_item_ids().is_empty()).is_true()
	assert_bool(station.has_complete_materials()).is_true()
	var job := Job.from_def(HAULING_DEF)
	job.target_node = station
	assert_bool(HAULING_DEF.is_available(job)).is_false()
	assert_bool(HAULING_DEF.should_close(job)).is_true()
	assert_bool(HAULING_DEF.job_complete(job)).is_true()


func test_queue_recipe_starts_order_and_emits_once() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	var counter := SignalCounter.new(EventBus.crafting_order_queued)
	assert_bool(station.queue_recipe("planks")).is_true()
	assert_bool(station.has_active_order()).is_true()
	assert_int(counter.read()).is_equal(1)
	# One active order per station in v1: a second queue is a no-op.
	assert_bool(station.queue_recipe("planks")).is_false()
	assert_int(station.remaining_need("plank")).is_equal(2)
	assert_array(station.needed_item_ids()).is_equal(["plank"])


func test_queue_unknown_recipe_is_noop() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	var counter := SignalCounter.new(EventBus.crafting_order_queued)
	assert_bool(station.queue_recipe("nonexistent")).is_false()
	assert_bool(station.has_active_order()).is_false()
	assert_int(counter.read()).is_equal(0)


func test_deposit_partial_then_crossing_fires_once() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	station.queue_recipe("planks")
	var colonist := _make_colonist()
	colonist.inventory.add("plank", 1)
	var counter := SignalCounter.new(EventBus.crafting_materials_ready)
	# Partial deposit: 1 of 2 — no crossing.
	assert_int(station.deposit_from(colonist)).is_equal(1)
	assert_int(station.remaining_need("plank")).is_equal(1)
	assert_int(station.given_count("plank")).is_equal(1)
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(0)
	# Crossing deposit: the second plank completes the order — single fire.
	colonist.inventory.add("plank", 1)
	assert_int(station.deposit_from(colonist)).is_equal(1)
	assert_bool(station.has_complete_materials()).is_true()
	# A further deposit takes nothing (given never decreases → no re-crossing).
	colonist.inventory.add("plank", 1)
	assert_int(station.deposit_from(colonist)).is_equal(0)
	assert_int(counter.read()).is_equal(1)


func test_hauling_fetches_for_station() -> void:
	# The haul def talks to job.target_node through the four sink methods only —
	# a queued station drives the same FETCH leg a blueprint does.
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	station.queue_recipe("planks")
	var crate := _make_crate("plank", 5)
	var job := Job.from_def(HAULING_DEF)
	job.target_node = station
	job.location = Vector3.ZERO
	var leg := HAULING_DEF.get_next_leg(_make_colonist(), job)
	assert_int(leg.kind).is_equal(HaulingJobDef.FETCH)
	assert_object(leg.target_node).is_same(crate)


# ── Colony routing ────────────────────────────────────────────────────────────

func test_order_queued_spawns_drought_persistent_haul_job() -> void:
	# queue_recipe emits → Colony spawns a haul job bound to the station even
	# with zero stock (the job waits on the board for restock).
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	_make_crate("plank", 0)
	var counter := SignalCounter.new(EventBus.crafting_order_queued)
	station.queue_recipe("planks")
	assert_int(counter.read()).is_equal(1)
	var spawned: Job = null
	for j in _test_board.get_jobs():
		if j.labor_id == "hauling":
			spawned = j
			break
	assert_object(spawned).is_not_null()
	assert_object(spawned.target_node).is_same(station)
	assert_bool(spawned.should_close()).is_false() # drought-waiting, not dead
	# A second queue (no-op) can't double the haul run; re-queue after clear
	# hits the anchor+labor dedupe.
	station.clear_order()
	station.queue_recipe("planks")
	var haul_count := 0
	for j in _test_board.get_jobs():
		if j.labor_id == "hauling":
			haul_count += 1
	assert_int(haul_count).is_equal(1)


func test_materials_ready_spawns_and_dedupes_craft_job() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	station.queue_recipe("planks")
	# Satisfy the order without going through hauling (direct deposits).
	var colonist := _make_colonist()
	colonist.inventory.add("plank", 2)
	var counter := SignalCounter.new(EventBus.crafting_materials_ready)
	station.deposit_from(colonist) # crossing → signal → Colony spawns craft job
	assert_int(counter.read()).is_equal(1)
	Colony._on_crafting_materials_ready(station, station.anchor_cell())
	var craft_jobs: Array[Job] = []
	for j in _test_board.get_jobs():
		if j.labor_id == "crafting":
			craft_jobs.append(j)
	assert_int(craft_jobs.size()).is_equal(1) # dedupe by anchor + labor
	assert_object(craft_jobs[0].target_node).is_same(station)
	assert_str(craft_jobs[0].title).is_equal("Craft planks")


# ── CraftingJobDef ────────────────────────────────────────────────────────────

func _workable_job(station: CraftingStation) -> Job:
	var job := Job.from_def(CRAFTING_DEF)
	job.target_node = station
	job.location = Vector3.ZERO
	return job


func _satisfied_order_station() -> CraftingStation:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	station.queue_recipe("planks")
	var colonist := _make_colonist()
	colonist.inventory.add("plank", 2)
	var counter := SignalCounter.new(EventBus.crafting_materials_ready)
	station.deposit_from(colonist)
	counter.read()
	return station


func test_craft_begin_uses_skill_multiplier() -> void:
	var station := _satisfied_order_station()
	var job := _workable_job(station)
	var leg := CRAFTING_DEF.get_next_leg(_make_colonist(), job)
	assert_object(leg).is_not_null()
	# No skill_set → raw base_time (4.0).
	var plain: Node = auto_free(Node.new()) as Node
	assert_float(CRAFTING_DEF.begin(plain, leg, job)).is_equal(4.0)
	# L1 colonist → 4.0 / 1.0.
	var colonist := _make_colonist()
	assert_float(CRAFTING_DEF.begin(colonist, leg, job)).is_equal(4.0)
	# L3 crafting (multiplier 1.4) → 4.0 / 1.4.
	colonist.skill_set.skills["crafting"] = {"level": 3, "progress": 0}
	var duration := CRAFTING_DEF.begin(colonist, leg, job)
	assert_bool(absf(duration - 4.0 / 1.4) < 0.001).is_true()


func test_craft_complete_produces_outputs_and_clears_order() -> void:
	var station := _satisfied_order_station()
	var colonist := _make_colonist()
	var job := _workable_job(station)
	var leg := CRAFTING_DEF.get_next_leg(colonist, job)
	CRAFTING_DEF.complete(colonist, leg, job)
	# Outputs landed in the crafter's carry inventory.
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(4)
	# The order is consumed: nothing owed, nothing active.
	assert_bool(station.has_active_order()).is_false()
	assert_bool(station.has_complete_materials()).is_true()
	# Post-complete: no next leg, job reports finished, job closes.
	assert_object(CRAFTING_DEF.get_next_leg(colonist, job)).is_null()
	assert_bool(CRAFTING_DEF.job_complete(job)).is_true()
	assert_bool(CRAFTING_DEF.should_close(job)).is_true()


func test_craft_complete_overflows_to_nearest_crate() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	station.queue_recipe("planks")
	var colonist := _make_colonist()
	colonist.inventory.add("plank", 2)
	var counter := SignalCounter.new(EventBus.crafting_materials_ready)
	station.deposit_from(colonist)
	counter.read()
	# Colony orders are crate-first: a crate with room for exactly 1 of the 4
	# output planks (plank = 1.5 kg) takes 1, the pocket gets the overflow.
	var crate := _make_crate("plank", 0)
	_test_registry.inventory_of(crate).capacity = 1.5
	var job := _workable_job(station)
	var leg := CRAFTING_DEF.get_next_leg(colonist, job)
	CRAFTING_DEF.complete(colonist, leg, job)
	assert_int(_test_registry.inventory_of(crate).get_item_count("plank")).is_equal(1)
	assert_int(colonist.inventory.get_item_count("plank")).is_equal(3)


func test_craft_def_lifecycle_gates() -> void:
	var station := _satisfied_order_station()
	var job := _workable_job(station)
	assert_bool(CRAFTING_DEF.is_available(job)).is_true()
	assert_bool(CRAFTING_DEF.should_close(job)).is_false()
	station.clear_order()
	assert_bool(CRAFTING_DEF.is_available(job)).is_false()
	assert_bool(CRAFTING_DEF.should_close(job)).is_true()
	job.target_node = null
	assert_bool(CRAFTING_DEF.should_close(job)).is_true()
	assert_bool(CRAFTING_DEF.is_available(job)).is_false()


func test_meets_requirements_ands_recipe_conditions() -> void:
	var station := _make_station([
		_recipe("gate3", ["plank", 1], ["plank", 1], 1.0, [_gate(3)]),
	])
	station.queue_recipe("gate3")
	var job := _workable_job(station)
	var colonist := _make_colonist() # crafting at L1 by default
	assert_bool(CRAFTING_DEF.meets_requirements(colonist, job)).is_false()
	colonist.skill_set.skills["crafting"] = {"level": 3, "progress": 0}
	assert_bool(CRAFTING_DEF.meets_requirements(colonist, job)).is_true()


# ── Attachment + data wiring + persistence ────────────────────────────────────

func test_furniture_layer_attaches_station_and_interaction() -> void:
	var layer := FurnitureLayer.new()
	layer.set_container(_container)
	var node := layer.spawn(WORKBENCH_DEF, Vector3i(10, 0, 10), 0)
	assert_object(node).is_not_null()
	var station := node.get_node_or_null("CraftingStation") as CraftingStation
	assert_object(station).is_not_null()
	assert_object(node.get_node_or_null("InteractionComponent")).is_not_null()
	# Recipes flow from def.crafting_params through the station's _ready.
	assert_int(station.recipes.size()).is_equal(2)


func test_workbench_tres_wires_crafting() -> void:
	# Data sanity: the def carries the capability + interaction wiring the
	# feature depends on.
	assert_object(WORKBENCH_DEF.crafting_params).is_not_null()
	assert_int(WORKBENCH_DEF.crafting_params.recipes.size()).is_equal(2)
	assert_bool(WORKBENCH_DEF.action_options.is_empty()).is_false()
	for recipe in WORKBENCH_DEF.crafting_params.recipes:
		assert_bool(recipe.inputs.size() > 0).is_true()
		assert_bool(recipe.outputs.size() > 0).is_true()


func test_furniture_serialize_round_trips_order() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	station.queue_recipe("planks")
	var colonist := _make_colonist()
	colonist.inventory.add("plank", 1)
	var counter := SignalCounter.new(EventBus.crafting_materials_ready)
	station.deposit_from(colonist)
	counter.read()
	var furniture := station.get_parent() as Furniture
	var data := furniture.serialize()
	# Restore into a fresh furniture + station (spawn recreates the child).
	var restored_furniture := Furniture.new()
	auto_free(restored_furniture)
	var restored := CraftingStation.new()
	restored.name = "CraftingStation"
	restored_furniture.add_child(restored)
	for r in station.recipes:
		restored.recipes.append(r)
	restored_furniture.deserialize(data)
	assert_bool(restored.has_active_order()).is_true()
	assert_int(restored.given_count("plank")).is_equal(1)
	assert_int(restored.remaining_need("plank")).is_equal(1)
	assert_str(restored.active_recipe().id).is_equal("planks")


# ── Dual-mode: worker reservation ─────────────────────────────────────────────

func test_player_order_crossing_emits_nothing_and_spawns_no_craft_job() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	assert_bool(station.queue_recipe("planks", CraftingStation.WORKER_PLAYER)).is_true()
	assert_str(station.worker()).is_equal(CraftingStation.WORKER_PLAYER)
	var colonist := _make_colonist()
	colonist.inventory.add("plank", 2)
	var ready := SignalCounter.new(EventBus.crafting_materials_ready)
	station.deposit_from(colonist)
	assert_int(ready.read()).is_equal(0)  # reserved: no colonist trigger fires
	assert_bool(station.is_ready()).is_true()
	assert_bool(station.can_player_work()).is_true()
	# Hauling still fed the ledger (order_queued fired at queue time) — but no
	# craft job may exist for a player order.
	var has_craft := false
	for j in _test_board.get_jobs():
		if j.labor_id == "crafting":
			has_craft = true
	assert_bool(has_craft).is_false()


func test_colony_order_crossing_still_spawns_craft_job() -> void:
	# Regression: the worker filter must not break the colony chain.
	var station := _satisfied_order_station()  # colony crossing already fired
	var craft_jobs := 0
	for j in _test_board.get_jobs():
		if j.labor_id == "crafting":
			craft_jobs += 1
	assert_int(craft_jobs).is_equal(1)


# ── Claim lock ────────────────────────────────────────────────────────────────

func test_claim_lock_arbitration() -> void:
	var station := _satisfied_order_station()
	assert_bool(station.claim("player")).is_true()
	assert_bool(station.can_player_work()).is_false()
	assert_bool(station.claim("c1")).is_false()    # a second claim is refused
	assert_bool(station.claim("player")).is_true() # idempotent for the owner
	station.release_claim("c1")                    # mismatched release no-ops
	assert_bool(station.is_claimed()).is_true()
	station.release_claim("player")
	assert_bool(station.is_claimed()).is_false()


func test_player_claim_blocks_colonist_work() -> void:
	var station := _satisfied_order_station()
	var colonist := _make_colonist()
	var job := _workable_job(station)
	var leg := JobLeg.new()
	leg.target_node = station
	assert_bool(station.claim("player")).is_true()
	# The colonist arrives mid-player-gauge: begin backs off (reports instant
	# so complete fires the same tick)…
	assert_float(CRAFTING_DEF.begin(colonist, leg, job)).is_equal(0.0)
	# …and complete no-ops on the claim guard — nothing produced, order intact.
	var crate := _make_crate("plank", 0)
	CRAFTING_DEF.complete(colonist, leg, job)
	assert_int(_test_registry.inventory_of(crate).get_item_count("plank")).is_equal(0)
	assert_bool(station.is_ready()).is_true()


func test_begin_claims_and_on_end_releases() -> void:
	var station := _satisfied_order_station()
	var colonist := _make_colonist()
	var job := _workable_job(station)
	var leg := JobLeg.new()
	leg.target_node = station
	CRAFTING_DEF.begin(colonist, leg, job)  # claims under the colonist's id
	assert_bool(station.is_claimed()).is_true()
	assert_str(station.claim_owner()).is_equal(colonist.colonist_id)
	CRAFTING_DEF.on_end(false, colonist, leg, job, 0.0)
	assert_bool(station.is_claimed()).is_false()


# ── Cancel + maintain orders ──────────────────────────────────────────────────

func test_cancel_refunds_ledger_and_closes_haul_job() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	station.queue_recipe("planks")  # colony order → haul job on the scratch board
	var colonist := _make_colonist()
	colonist.inventory.add("plank", 1)
	var ready := SignalCounter.new(EventBus.crafting_materials_ready)
	station.deposit_from(colonist)  # partial: 1/2
	ready.read()
	var crate := _make_crate("plank", 0)
	station.cancel_order()
	assert_bool(station.has_active_order()).is_false()
	assert_int(_test_registry.inventory_of(crate).get_item_count("plank")).is_equal(1)
	# The bound haul job self-cleans: a no-order station reads satisfied.
	var haul: Job = null
	for j in _test_board.get_jobs():
		if j.labor_id == "hauling":
			haul = j
	assert_object(haul).is_not_null()
	assert_bool(haul.should_close()).is_true()


func test_colony_stock_sums_crates() -> void:
	_make_crate("plank", 3)
	_make_crate("plank", 4)
	_make_crate("axe", 1)
	assert_int(_test_registry.colony_stock("plank")).is_equal(7)
	assert_int(_test_registry.colony_stock("axe")).is_equal(1)
	assert_int(_test_registry.colony_stock("stone_block")).is_equal(0)


## Deposit a full order for the active recipe via `colonist`, then run the
## craft def's complete (crate-first output routing).
func _satisfy_and_complete(station: CraftingStation, colonist: Colonist) -> void:
	var ready := SignalCounter.new(EventBus.crafting_materials_ready)
	colonist.inventory.add("plank", 2)
	station.deposit_from(colonist)
	ready.read()
	var leg := JobLeg.new()
	leg.target_node = station
	CRAFTING_DEF.complete(colonist, leg, _workable_job(station))


func test_maintain_order_requeues_until_stock_target() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	var goal := {"item_id": "plank", "count": 10}
	assert_bool(station.queue_recipe("planks", CraftingStation.WORKER_COLONY, goal)).is_true()
	var _crate := _make_crate("plank", 0)
	var colonist := _make_colonist()
	# Craft 1: stock 0+4 < 10 → fresh order requeued with the same goal.
	_satisfy_and_complete(station, colonist)
	assert_bool(station.has_active_order()).is_true()
	assert_int(station.remaining_need("plank")).is_equal(2)
	assert_int(station.maintain_goal().get("count", 0)).is_equal(10)
	# Craft 2: stock 8 < 10 → requeue again.
	_satisfy_and_complete(station, colonist)
	assert_bool(station.has_active_order()).is_true()
	# Craft 3: stock 12 ≥ 10 → the order clears for good.
	_satisfy_and_complete(station, colonist)
	assert_bool(station.has_active_order()).is_false()
	assert_int(_test_registry.colony_stock("plank")).is_equal(12)


# ── Player SkillSet + CraftAction ─────────────────────────────────────────────

func test_player_skillset_wired_and_conditions_evaluate() -> void:
	var player := _make_player()
	assert_object(player.skill_set).is_not_null()
	var gate := _gate(2)
	assert_bool(gate.is_met(player, null)).is_false()  # fresh player reads L1
	player.skill_set.skills["crafting"] = {"level": 3, "progress": 0}
	assert_bool(gate.is_met(player, null)).is_true()
	assert_float(player.skill_set.get_multiplier("crafting")).is_equal(1.4)


func test_craft_action_instant_path_produces_for_player() -> void:
	var station := _make_station([_recipe("free", ["plank", 1], ["axe", 1], 0.0)])
	station.queue_recipe("free", CraftingStation.WORKER_PLAYER)
	var player := _make_player()
	player.inventory.add("plank", 1)
	var ready := SignalCounter.new(EventBus.crafting_materials_ready)
	station.deposit_from(player)  # the player deposits their own materials
	assert_int(ready.read()).is_equal(0)  # reserved order: no colonist trigger
	var action := CraftAction.new()
	action.execute(player, station)  # base_time 0 → instant path, no gauge
	# Pocket-first: the player crafting personally is how the player gets it.
	assert_int(player.inventory.get_item_count("axe")).is_equal(1)
	assert_bool(station.has_active_order()).is_false()
	# Personal crafting trains the player's crafting skill.
	assert_int(int(player.skill_set.skills.get("crafting", {}).get("progress", 0))).is_equal(1)


func test_craft_action_guarded_when_not_workable() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	var player := _make_player()
	var action := CraftAction.new()
	action.execute(player, station)  # no order at all → no-op
	assert_bool(station.has_active_order()).is_false()
	station.queue_recipe("planks", CraftingStation.WORKER_PLAYER)
	action.execute(player, station)  # queued but not ready → no-op
	assert_bool(station.is_ready()).is_false()
	assert_int(player.inventory.get_item_count("plank")).is_equal(0)


func test_work_done_round_trips_through_state_bag() -> void:
	var station := _make_station([_recipe("planks", ["plank", 2], ["plank", 4], 4.0)])
	station.queue_recipe("planks", CraftingStation.WORKER_PLAYER)
	station.set_work_done(1.25)
	assert_float(station.work_done()).is_equal(1.25)
	var furniture := station.get_parent() as Furniture
	var data := furniture.serialize()
	var restored_furniture := Furniture.new()
	auto_free(restored_furniture)
	var restored := CraftingStation.new()
	restored.name = "CraftingStation"
	restored_furniture.add_child(restored)
	for r in station.recipes:
		restored.recipes.append(r)
	restored_furniture.deserialize(data)
	assert_float(restored.work_done()).is_equal(1.25)
	assert_str(restored.worker()).is_equal(CraftingStation.WORKER_PLAYER)
