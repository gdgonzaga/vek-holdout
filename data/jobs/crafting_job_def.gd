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
##
## A null leg is always a clean finish here, so the base job_complete (true)
## is inherited: this job only spawns on a ready order, deposits never
## regress, and complete_order's maintain requeue leaves a fresh NOT-ready
## order — every null-leg case follows a successful craft. The hauler's stall
## semantics don't apply.

const CRAFTING_LABOR := "crafting"  # the labor_id authored in crafting.tres


## Single WORK leg targeting the station, available exactly while it holds a
## materials-complete, unclaimed order (a claim held by the player's gauge
## stops legs — the colonist's complete no-ops and the job ends without
## looping). complete() resolves the order, so the post-complete get_next_leg
## returns null — the clean end-signal for this colonist (the construction
## pattern).
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
## works at base_time). A timed WORK phase CLAIMS the station under the
## colonist's id; if the player's gauge already holds the claim, begin reports
## instant — complete() re-checks and no-ops, and the job ends cleanly instead
## of double-producing. 0.0 (instant) if the order vanished.
func begin(actor: Node, leg: JobLeg, _job: Job) -> float:
	var station := _station_from(leg.target_node)
	var recipe := station.active_recipe() if station != null else null
	if recipe == null:
		return 0.0
	var colonist := actor as Colonist
	if colonist == null or colonist.skill_set == null:
		return recipe.base_time
	var duration := recipe.base_time / colonist.skill_set.get_multiplier(labor_id)
	if duration > 0.0 and not station.claim(colonist.colonist_id):
		return 0.0
	return duration


## Consume the order and produce its outputs. Colony orders deposit to the
## nearest crate FIRST (pocket takes the overflow) — a maintain order's stock
## counter only sees what's physically in storage, so production must land
## there; player-worked orders (the CraftAction path shares this routing)
## prefer the crafter's pocket. The claim re-check is the race guard: if the
## player's gauge took the order while this colonist walked here, produce
## nothing and let the job end. Ends through complete_order, which requeues a
## maintain order still short of its stock target. XP is automatic:
## ColonistAI's _end_job records the labor use.
func complete(actor: Node, leg: JobLeg, _job: Job) -> void:
	var station := _station_from(leg.target_node)
	var recipe := station.active_recipe() if station != null else null
	if recipe == null:
		return
	var colonist := actor as Colonist
	if not station.claim(colonist.colonist_id if colonist != null else ""):
		return
	var pocket_first: bool = station.worker() == CraftingStation.WORKER_PLAYER
	var produced := produce(actor, station, recipe, pocket_first)
	station.complete_order()
	if produced:
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


## Claimable while the station holds a materials-complete, unclaimed order.
## The unclaimed half matters while this job's own colonist is mid-WORK (self-
## claimed): no second claim, and selection skips it — max_assignees=1 already
## enforces this; the check keeps the poll honest. The job is only spawned on
## the materials crossing, and `given` never decreases within an order, so
## availability otherwise flips false exactly when the order resolves or the
## station is freed.
func is_available(job: Job) -> bool:
	return _workable(job)


## Leaves the board when the station is gone or its order resolved. Materials
## readiness is intentionally NOT a close condition (it can't regress — see
## is_available); unlike a haul job there is no drought state to wait out.
func should_close(job: Job) -> bool:
	var station := _station_of_job(job)
	return station == null or not station.has_active_order()


## Release this colonist's claim when leaving the job (clean finish, abort,
## claim-path miss — leg null). Owner-matched: a mismatched release is a no-op,
## so an aborting colonist can't unlock the player's running gauge.
## complete_order already releases on the normal path; this covers the aborts.
func on_end(_success: bool, actor: Node, leg: JobLeg, _job: Job, _elapsed: float) -> void:
	var station := _station_from(leg.target_node) if leg != null else null
	if station == null:
		return
	var colonist := actor as Colonist
	station.release_claim(colonist.colonist_id if colonist != null else "")


func _workable(job: Job) -> bool:
	var station := _station_of_job(job)
	return station != null and not station.is_paused() and not station.is_claimed() \
			and station.has_active_order() and station.has_complete_materials()


func _station_of_job(job: Job) -> CraftingStation:
	return _station_from(job.target_node)


func _station_from(node: Node) -> CraftingStation:
	if node == null or not is_instance_valid(node):
		return null
	return node as CraftingStation


## Produce the recipe's outputs, preferring `pocket_first`'s target and
## overflowing into the other (a crafter with no inventory overflows wholly to
## the crate; no crate → the pocket; neither → dropped, hauling's known gap).
## Returns true when at least one item landed somewhere. Public because the
## def owns the craft math — CraftAction (the player's personal craft) reuses
## this with pocket_first = true.
func produce(actor: Node, station: CraftingStation, recipe: RecipeDef, pocket_first: bool) -> bool:
	var pocket := _pocket_of(actor)
	var crate_inv := _crate_near(station)
	var produced := false
	for entry in recipe.outputs:
		var id := entry.item_def.id
		var overflow: int = entry.count
		if pocket_first and pocket != null:
			overflow = pocket.add(id, entry.count)
		elif crate_inv != null:
			overflow = crate_inv.add(id, entry.count)
		if overflow > 0:
			if pocket_first and crate_inv != null:
				crate_inv.add(id, overflow)
			elif not pocket_first and pocket != null:
				pocket.add(id, overflow)
		if overflow < entry.count:
			produced = true
	return produced


func _pocket_of(actor: Node) -> Inventory:
	var colonist := actor as Colonist
	if colonist != null and colonist.inventory != null:
		return colonist.inventory
	var player := actor as Player
	if player != null and player.inventory != null:
		return player.inventory
	return null


func _crate_near(station: CraftingStation) -> StorageInventory:
	var origin := Vector3.ZERO
	var furniture := station.get_parent() as Node3D
	if furniture != null:
		origin = furniture.global_position
	return Colony.storage_registry.inventory_of(
		Colony.storage_registry.nearest_crate(origin))
