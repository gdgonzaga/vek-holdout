extends JobDef
class_name HaulingJobDef
## Hauling labor (GDD §6.10, ARCH "Subsystem: Colonists"): carry materials from
## storage crates to a MaterialSink (material_sink.gd — blueprints today, crafting
## stations next) until its need is satisfied. A multi-colonist job — up to
## max_assignees haulers divvy a run through the sink's shared deposit counter
## (no per-colonist slices): each independently loops FETCH (crate→inventory) →
## DELIVER (deposit_from the sink) until has_complete_materials(). The crate's
## live stock serializes concurrent haulers, so two can't double-spend a plank.
##
## Job shape: job.target_node is the MaterialSink being supplied; each leg's
## target_node is the per-leg node (crate on FETCH, sink on DELIVER). Phase
## is derived from carry state (not stored): carrying a still-needed material →
## DELIVER; otherwise FETCH from the nearest source crate; no source → null
## (this colonist yields — the job stays on the board waiting for restock, see
## should_close). Both legs are instant (begin returns 0) — hauling has no
## WORK phase.
##
## Chaining: the DELIVER leg calls the sink's deposit_from, which emits the
## sink's own materials-ready signal when it crosses has_complete_materials
## (blueprint_materials_ready for blueprints) — Colony's single trigger to spawn
## the follow-on job. So the haul job itself never spawns it; it just keeps
## delivering until satisfied.

const FETCH := 1
const DELIVER := 2


## Next leg for `actor`, derived from its carry state and the sink's still-
## unsatisfied materials. Returns null when the colonist has no further work:
## sink gone, materials satisfied, or nothing to fetch and nothing carried.
func get_next_leg(actor: Node, job: Job) -> JobLeg:
	var sink := job.target_node
	if not MaterialSink.is_material_sink(sink):
		return null
	if sink.has_complete_materials():
		return null
	var colonist := actor as Colonist
	if colonist == null:
		return null
	# Carrying any material this sink still needs → deliver it. Material-
	# specific (not bare "inventory non-empty") so a future carried tool — or
	# orphan items from a prior failed cleanup — don't send us to deliver
	# pointlessly (deposit_from would take nothing and we'd loop forever).
	if _carries_needed_material(colonist, sink):
		var deliver := JobLeg.new()
		deliver.location = job.location
		deliver.target_node = sink
		deliver.kind = DELIVER
		return deliver
	# No room for even one unit (a carried tool / orphan items clogging capacity)
	# → end this colonist's run; on_end empties the non-needed items to a crate
	# and the next claim retries clean. Self-heals instead of hot-looping
	# crate→noop-fetch→deliver-nothing→crate.
	if colonist.remaining_capacity() <= 0.0:
		return null
	# Empty (or only carrying non-needed items) → fetch from the nearest crate
	# that holds one of the still-needed materials. No source → yield for now
	# (null). The job stays registered through the drought — should_close ignores
	# source stock — and is_available turns it claimable again once a crate
	# restocks, so the idle poll resumes hauling without any producer event.
	var crate := Colony.storage_registry.find_source(sink.needed_item_ids(), colonist.global_position)
	if crate == null:
		return null
	var fetch := JobLeg.new()
	fetch.location = crate.global_position
	fetch.target_node = crate
	fetch.kind = FETCH
	return fetch


## Haul legs are instant (an inventory transfer / a deposit); no WORK tick.
func begin(_actor: Node, _leg: JobLeg, _job: Job) -> float:
	return 0.0


## Apply the leg. FETCH withdraws still-needed materials (up to capacity) from
## the crate into the colonist; DELIVER deposits the colonist's load into the
## sink via its deposit_from. Need is read through the MaterialSink contract —
## no Blueprint/material_cost knowledge here, so the same legs feed any
## haulable furniture (crafting stations next).
func complete(actor: Node, leg: JobLeg, job: Job) -> void:
	var sink := job.target_node
	if not MaterialSink.is_material_sink(sink):
		return
	if leg.kind == FETCH:
		# Skip if the sink was satisfied while we walked here — avoids a
		# pointless withdraw we'd just return in on_end.
		if sink.has_complete_materials():
			return
		var crate_inv := Colony.storage_registry.inventory_of(leg.target_node)
		var colonist := actor as Colonist
		if crate_inv == null or colonist == null or colonist.inventory == null:
			return
		for id in sink.needed_item_ids():
			var remaining: int = sink.remaining_need(id)
			if remaining <= 0:
				continue
			# transfer_to moves up to `remaining` from the crate into the
			# colonist, clamped by what the crate holds and the colonist's
			# capacity. Live crate stock serializes concurrent haulers.
			crate_inv.transfer_to(colonist.inventory, id, remaining)
	elif leg.kind == DELIVER:
		# deposit_from takes up to each material's remaining need from the
		# colonist; self-limits, and the sink emits its own materials-ready
		# signal on the crossing (blueprint_materials_ready today) — Colony's
		# single trigger to spawn the follow-on job.
		sink.deposit_from(actor)


## On leaving the job (clean finish or abort), return any items still on the
## colonist to the nearest crate so they're not lost or carried into the next
## job. Surplus arises when a parallel hauler satisfied the blueprint while this
## one was mid-fetch, or when a fetch over-drew against a need later filled by
## the player. Carried TOOLS are exempt — a fetched axe must survive a haul run
## (harvesting's FETCH_TOOL pattern depends on it), so tool-tagged items stay
## with the colonist. Items with no home (no crate / all full) also stay — a
## known minor gap.
func on_end(_success: bool, actor: Node, _leg: JobLeg, _job: Job, _elapsed: float) -> void:
	var colonist := actor as Colonist
	if colonist == null or colonist.inventory == null:
		return
	var crate := Colony.storage_registry.nearest_crate(colonist.global_position)
	var crate_inv := Colony.storage_registry.inventory_of(crate)
	if crate_inv == null:
		return
	for item_id in colonist.inventory.items.keys():
		if _is_tool(item_id):
			continue
		var count: int = colonist.inventory.get_item_count(item_id)
		if count > 0:
			colonist.inventory.transfer_to(crate_inv, item_id, count)


const TOOL_TAG := "tool"

func _is_tool(item_id: String) -> bool:
	var def := ItemDB.get_def(item_id)
	return def != null and def.tags.has(TOOL_TAG)


## A haul job is claimable while its sink exists, is still unsatisfied, and
## some crate holds a still-needed material. The slot half of the gate (colonists
## < max_assignees) lives on Job.is_available; this is the labor-specific half.
## Claimability only — NOT lifetime: a drought (unsatisfied sink, no stocking
## crate) makes the job invisible to selection but should_close keeps it
## registered until restock.
func is_available(job: Job) -> bool:
	var sink := job.target_node
	if not MaterialSink.is_material_sink(sink):
		return false
	if sink.has_complete_materials():
		return false
	return Colony.storage_registry.has_source_for(sink.needed_item_ids())


## A haul job leaves the board only when its sink is gone or satisfied — NOT
## when the source dries up. A drought makes the job unclaimable (is_available
## false, so selection skips it) while keeping it registered: the idle poll
## re-checks has_source_for every 0.5s, and a restocked crate flips the job
## claimable again without any producer event. This is the targeted form of the
## persistence job-extensions.md defers for scheduled labors.
func should_close(job: Job) -> bool:
	var sink := job.target_node
	if not MaterialSink.is_material_sink(sink):
		return true
	return sink.has_complete_materials()


## A null leg is a clean finish only when the sink crossed
## has_complete_materials; otherwise the hauler stalled short of the need
## (drained crates) and the run is incomplete — no success XP, and ColonistAI
## logs a waiting-for-materials entry. False exactly while the job lingers on
## the board unsatisfied.
func job_complete(job: Job) -> bool:
	var sink := job.target_node
	return MaterialSink.is_material_sink(sink) and sink.has_complete_materials()


func _carries_needed_material(colonist: Colonist, sink: Node) -> bool:
	if colonist == null or colonist.inventory == null:
		return false
	for id in sink.needed_item_ids():
		if colonist.inventory.get_item_count(id) > 0:
			return true
	return false
