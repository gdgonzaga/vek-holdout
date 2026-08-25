extends JobDef
class_name CraftingJobDef
## Crafting labor (GDD §7.9, ARCH "Crafting"): work a station's ready order
## over recipe.base_time, then produce the outputs and resolve the order.
## job.target_node is the CraftingStation node (not the furniture) — it IS the
## MaterialSink. The job only spawns once the order's deposits cross
## has_complete_materials (crafting_materials_ready), and `given` never
## regresses within an order, so an existing job is always workable — until
## the order resolves or the station is freed/paused/claimed.
##
## Dual-mode arbitration: a WORK cycle claims the station under the colonist's
## id (CraftingStation.claim) so the player's Craft-now gauge and a colonist
## can't double-produce one order; complete() re-checks the claim and no-ops
## if the player took it while the colonist walked there.

const CRAFTING_LABOR := "crafting"  # the labor_id authored in crafting.tres


## Cycle duration: the active recipe's authored base_time (skill scaling is
## applied by PerformWork). 0.0 with no resolvable recipe — falls back to the
## authored work_duration.
func begin(_actor: Node, job: Variant) -> float:
	var station := _station_of_job(job)
	var recipe := station.active_recipe() if station != null else null
	return recipe.base_time if recipe != null else 0.0


## Produce the order's outputs and resolve it. Ordering matters for maintain
## orders: _finish drops this job from the board BEFORE complete_order can
## requeue (queue_recipe -> crafting_order_queued -> Colony's spawn), so the
## dedupe-by-anchor check doesn't see the spent job and the follow-on haul
## job really spawns. Skips _finish entirely when the claim race was lost —
## the job stays for a later retry.
func complete(actor: Node, job: Variant) -> void:
	var station := _station_of_job(job)
	if station == null or not station.is_ready():
		_finish(actor, job)
		return
	var colonist := actor as Colonist
	if not station.claim(colonist.colonist_id if colonist != null else ""):
		return
	_finish(actor, job)
	var recipe := station.active_recipe()
	var produced := station.produce(actor)
	station.complete_order()
	if produced and recipe != null:
		GameLog.craft("Crafted %s" % recipe.label())


## Base conditions AND the active recipe's own gates (RecipeDef.conditions —
## e.g. MinSkillCondition). Evaluated fresh every poll; an orderless job has
## no recipe gates to fail.
func meets_requirements_any(actor: Node, job: Variant) -> bool:
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


## Claimable while the station holds a materials-complete, unclaimed, live
## order (the paused flag is the player's colonist-work override).
func is_available(job: Variant) -> bool:
	return _workable(job)


## Leaves the board when the station is gone or its order resolved. Materials
## readiness is NOT a close condition (it can't regress); there is no drought
## state to wait out.
func should_close(job: Variant) -> bool:
	var station := _station_of_job(job)
	return station == null or not station.has_active_order()


## Preempted mid-craft: release this colonist's claim so the order isn't left
## locked forever (claims are runtime-only; the needs branch can preempt the
## work subtree mid-cycle). Owner-matched — can't unlock the player's gauge.
func on_abort(actor: Node, job: Variant, _elapsed: float) -> void:
	var station := _station_of_job(job)
	if station == null:
		return
	var colonist := actor as Colonist
	station.release_claim(colonist.colonist_id if colonist != null else "")


func _workable(job: Variant) -> bool:
	var station := _station_of_job(job)
	return station != null and not station.is_paused() and not station.is_claimed() \
			and station.has_active_order() and station.has_complete_materials()


func _station_of_job(job: Variant) -> CraftingStation:
	if job == null or not "target_node" in job:
		return null
	var t: Variant = job.target_node
	if t == null or not is_instance_valid(t):
		return null
	return t as CraftingStation
