extends JobDef
class_name CraftingJobDef
## Crafting labor (GDD §6.10/§7.9): work a station's active order over
## recipe.base_time, then consume the deposited inputs and hand the outputs to
## the crafter. Single-leg like construction: get_next_leg returns the station
## leg once (walk to a stand-adjacent cell), begin reports the skill-scaled
## duration, complete clears the order and produces.
##
## job.target_node is the CraftingStation node (not the furniture) — it IS the
## MaterialSink, and freeing the furniture frees the station too, so
## ColonistAI's freed-target guard covers a deconstructed workbench unchanged.
##
## Spawned by Colony only when the order's deposits cross
## has_complete_materials (crafting_materials_ready — the haul run feeding the
## station triggers this job), so get_next_leg never hands out a leg for an
## unstocked order. Deposits can't regress (given never decreases within an
## order), which is why is_available doesn't re-check sources: once ready,
## always ready until crafted.
##
## Recipe-level skill gates live on RecipeDef.conditions (not this def's
## conditions array — those are per-def, identical for every recipe); meets_
## requirements ANDs them in, evaluated hot so a leveled-up colonist becomes
## eligible on the next poll.

const CRAFTING_LABOR := "crafting"


## Single WORK leg targeting the station, available exactly while it holds a
## materials-complete order. complete() clears the order, so the post-complete
## get_next_leg returns null — the clean end-signal for this colonist (the
## construction pattern: without the order guard we'd hand back a leg to a
## cleared station and end on the abort path instead of the success path).
func get_next_leg(_actor: Node, job: Job) -> JobLeg:
	if not _workable(job):
		return null
	# `location` is the footprint-center approach Colony sets at spawn; the AI
	# refines it into an adjacent standing cell. target_node is the station.
	var leg := JobLeg.new()
	leg.location = job.location
	leg.target_node = job.target_node
	return leg


## recipe.base_time divided by the crafter's skill multiplier for this def's
## labor (the ConstructionJobDef.begin pattern; L1 = 1.0, so a fresh colonist
## works at base_time). 0.0 (instant) if the order vanished — complete() will
## no-op and the job ends without a WORK tick.
func begin(actor: Node, leg: JobLeg, _job: Job) -> float:
	var station := _station_from(leg.target_node)
	var recipe := station.active_recipe() if station != null else null
	if recipe == null:
		return 0.0
	var colonist := actor as Colonist
	if colonist == null or colonist.skill_set == null:
		return recipe.base_time
	return recipe.base_time / colonist.skill_set.get_multiplier(labor_id)


## Consume the order and produce its outputs: into the crafter's carry
## inventory first, overflow to the nearest crate (StorageRegistry), mirroring
## how hauling's on_end rehomes items. Clearing the order IS the consumption —
## deposits were virtual (counted in the station's `given`, never physically
## stored). XP is automatic: ColonistAI's _end_job records the labor use.
func complete(actor: Node, leg: JobLeg, _job: Job) -> void:
	var station := _station_from(leg.target_node)
	var recipe := station.active_recipe() if station != null else null
	if recipe == null:
		return
	var colonist := actor as Colonist
	for entry in recipe.outputs:
		var id := entry.item_def.id
		var overflow: int = entry.count
		if colonist != null and colonist.inventory != null:
			overflow = colonist.inventory.add(id, entry.count)
		if overflow > 0:
			_overflow_to_crate(actor, id, overflow)
	station.clear_order()
	GameLog.craft("Crafted %s" % recipe.label())


## Base conditions AND the active recipe's own gates (RecipeDef.conditions —
## e.g. MinSkillCondition). Evaluated fresh every poll/claim per the
## JobDef.conditions contract; an orderless job has no recipe gates to fail.
func meets_requirements(actor: Node, job: Job) -> bool:
	if not super(actor, job):
		return false
	var station := _station_of_job(job)
	if station == null:
		return true
	var recipe := station.active_recipe()
	if recipe == null:
		return true
	for condition in recipe.conditions:
		if not condition.is_met(actor, station):
			return false
	return true


## Claimable while the station holds a materials-complete order. The job is
## only spawned on that crossing, and `given` never decreases within an order,
## so this flips false exactly when the order is crafted/cleared or the
## station is freed.
func is_available(job: Job) -> bool:
	return _workable(job)


## Leaves the board when the station is gone or its order resolved. Materials
## readiness is intentionally NOT a close condition (it can't regress — see
## is_available); unlike a haul job there is no drought state to wait out.
func should_close(job: Job) -> bool:
	var station := _station_of_job(job)
	return station == null or not station.has_active_order()


## A null leg is a clean finish when the order is gone (complete cleared it).
## An order still active means the run was cut short before completing.
func job_complete(job: Job) -> bool:
	var station := _station_of_job(job)
	return station == null or not station.has_active_order()


func _workable(job: Job) -> bool:
	var station := _station_of_job(job)
	return station != null and station.has_active_order() and station.has_complete_materials()


func _station_of_job(job: Job) -> CraftingStation:
	return _station_from(job.target_node)


func _station_from(node: Node) -> CraftingStation:
	if node == null or not is_instance_valid(node):
		return null
	return node as CraftingStation


func _overflow_to_crate(actor: Node, item_id: String, count: int) -> void:
	var origin := Vector3.ZERO
	if actor is Node3D:
		origin = (actor as Node3D).global_position
	var crate := Colony.storage_registry.nearest_crate(origin)
	var crate_inv := Colony.storage_registry.inventory_of(crate)
	if crate_inv == null:
		return  # no home: dropped (the same known gap as hauling's on_end)
	crate_inv.add(item_id, count)
