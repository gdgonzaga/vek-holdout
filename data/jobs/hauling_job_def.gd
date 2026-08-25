extends JobDef
class_name HaulingJobDef
## Hauling labor (GDD §6.10, ARCH "Subsystem: Colonists"): carry materials from
## storage crates to a MaterialSink (material_sink.gd — blueprints and crafting
## stations today) until its need is satisfied. Multi-colonist
## (max_assignees=3): haulers share the sink's deposit counter, and live crate
## stock serializes concurrent runs so two can't double-spend a plank.
##
## Expressed as repeated cycles through the universal work tree — no dedicated
## leg tree. Each cycle: ClaimJob re-claims, work_site() picks the walk target
## from carry state (carrying a still-needed material -> the sink; empty ->
## the nearest crate stocking a needed material), NavigateTo walks it, then
## PerformWork fires complete() which does the instant transfer (FETCH from
## the crate into the pocket, or DELIVER via the sink's deposit_from) and
## releases the claim WITHOUT ending the job — the next claim starts the next
## cycle. The loop ends when the sink is satisfied: is_available goes false,
## the prune drops the job, and ClaimJob moves on.
##
## Drought persistence: with no crate stocking a needed material the job is
## unclaimable (is_available false — selection skips it) but stays registered
## (should_close ignores source stock), so a restocked crate resumes hauling
## with no new producer event (Colony's haul spawn is single-fire).


## Walk target for this cycle: the sink while carrying a material it still
## needs, else the nearest crate stocking one. Null (board default) never
## applies — an empty-handed hauler with no source can't be mid-job (see
## is_available), but returning null keeps ClaimJob's fallback harmless.
func work_site(actor: Node, job: Variant) -> Variant:
	var sink := _sink_of(job)
	if sink == null:
		return null
	if _carries_needed_material(actor, sink):
		var loc: Vector3 = job.location if "location" in job else Vector3.ZERO
		return loc
	var crate := Colony.storage_registry.find_source(
			sink.needed_item_ids(), (actor as Node3D).global_position if actor is Node3D else Vector3.ZERO)
	if crate == null:
		return null
	return crate.global_position


## The cycle's transfer. Carrying a needed material -> DELIVER (the sink's
## deposit_from, which emits the sink's own materials-ready signal on the
## crossing — Colony's single trigger for the follow-on construction/craft
## job). Otherwise -> FETCH: withdraw still-needed materials from the nearest
## source crate into the pocket, clamped by remaining need, crate stock, and
## pocket capacity. Never calls _finish — hauling ends by satisfaction, not
## by one terminal cycle.
func complete(actor: Node, job: Variant) -> void:
	var sink := _sink_of(job)
	if sink == null or not is_instance_valid(actor):
		return
	if _carries_needed_material(actor, sink):
		sink.deposit_from(actor)
		if sink.has_complete_materials():
			_return_surplus_to_crate(actor)
		return
	var crate := Colony.storage_registry.find_source(
			sink.needed_item_ids(), (actor as Node3D).global_position if actor is Node3D else Vector3.ZERO)
	var crate_inv := Colony.storage_registry.inventory_of(crate) if crate != null else null
	if crate_inv == null:
		return
	var pocket: Inventory = actor.inventory if "inventory" in actor and actor.inventory != null else null
	if pocket == null:
		return
	for id in sink.needed_item_ids():
		var remaining: int = sink.remaining_need(id)
		if remaining <= 0:
			continue
		# transfer_to moves up to `remaining`, clamped by crate stock and the
		# colonist's capacity. Live crate stock serializes concurrent haulers.
		crate_inv.transfer_to(pocket, id, remaining)


## Claimable while the sink exists, is still unsatisfied, and some crate holds
## a still-needed material. Claimability only — NOT lifetime: a drought makes
## the job invisible to selection while should_close keeps it registered.
func is_available(job: Variant) -> bool:
	var sink := _sink_of(job)
	if sink == null:
		return false
	if sink.has_complete_materials():
		return false
	return Colony.storage_registry.has_source_for(sink.needed_item_ids())


## Leaves the board only when the sink is gone or satisfied — NOT when the
## source dries up (the drought-wait; see class doc).
func should_close(job: Variant) -> bool:
	var sink := _sink_of(job)
	if sink == null:
		return true
	return sink.has_complete_materials()


## A finished cycle satisfied the work only when the sink crossed
## has_complete_materials; a stalled run (drained crates) is not a completion.
func job_complete(job: Variant) -> bool:
	var sink := _sink_of(job)
	return sink != null and sink.has_complete_materials()


## A parallel hauler (or the player) satisfied the sink while this colonist
## was mid-fetch: return the now-unneeded load to the nearest crate so it
## isn't lost or carried into the next job. Carried TOOLS are exempt — a
## fetched axe must survive a haul run (harvesting's tool-fetch depends on
## it). Items with no home stay with the colonist — a known minor gap.
func _return_surplus_to_crate(actor: Node) -> void:
	var pocket: Inventory = actor.inventory if "inventory" in actor and actor.inventory != null else null
	if pocket == null or not actor is Node3D:
		return
	var crate_inv := Colony.storage_registry.inventory_of(
			Colony.storage_registry.nearest_crate((actor as Node3D).global_position))
	if crate_inv == null:
		return
	for item_id in pocket.items.keys():
		if _is_tool(str(item_id)):
			continue
		var count: int = pocket.get_item_count(str(item_id))
		if count > 0:
			pocket.transfer_to(crate_inv, str(item_id), count)


const TOOL_TAG := "tool"


func _is_tool(item_id: String) -> bool:
	var def := ItemDB.get_def(item_id)
	return def != null and def.tags.has(TOOL_TAG)


func _sink_of(job: Variant) -> Node:
	if job == null or not "target_node" in job:
		return null
	var t: Variant = job.target_node
	if t == null or not is_instance_valid(t) or (t as Node).is_queued_for_deletion():
		return null
	var n := t as Node
	if n == null or not MaterialSink.is_material_sink(n):
		return null
	return n


func _carries_needed_material(actor: Node, sink: Node) -> bool:
	if actor == null or not "inventory" in actor or actor.inventory == null:
		return false
	# Material-specific (not bare "inventory non-empty") so a carried tool —
	# or orphan items from a prior failed cleanup — never sends us to deliver
	# pointlessly (deposit_from would take nothing and we'd loop forever).
	for id in sink.needed_item_ids():
		if actor.inventory.get_item_count(id) > 0:
			return true
	return false
