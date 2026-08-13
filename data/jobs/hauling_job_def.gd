extends JobDef
class_name HaulingJobDef
## Hauling labor (GDD §6.10, ARCH "Subsystem: Colonists"): carry materials from
## storage crates to a blueprint until its material_cost is satisfied, then hand
## off to construction. A multi-colonist job — up to max_assignees haulers divvy
## a run through the blueprint's shared deposit counter (no per-colonist slices):
## each independently loops FETCH (crate→inventory) → DELIVER (deposit_from the
## blueprint) until has_complete_materials(). The crate's live stock serializes
## concurrent haulers, so two can't double-spend the same plank.
##
## Job shape: job.target_node is the blueprint being supplied; each leg's
## target_node is the per-leg node (crate on FETCH, blueprint on DELIVER). Phase
## is derived from carry state (not stored): carrying a still-needed material →
## DELIVER; otherwise FETCH from the nearest source crate; no source → null
## (this colonist gives up; the job may close or another source may appear
## later). Both legs are instant (begin returns 0) — hauling has no WORK phase.
##
## Chaining: the DELIVER leg calls Blueprint.deposit_from, which emits
## blueprint_materials_ready when it crosses has_complete_materials — Colony's
## single trigger to spawn the construction job. So the haul job itself never
## spawns construction; it just keeps delivering until satisfied.

const FETCH := 1
const DELIVER := 2


## Next leg for `actor`, derived from its carry state and the blueprint's still-
## unsatisfied materials. Returns null when the colonist has no further work:
## blueprint gone, materials satisfied, or nothing to fetch and nothing carried.
func get_next_leg(actor: Node, job: Job) -> JobLeg:
	var bp := job.target_node as Blueprint
	if bp == null or not is_instance_valid(bp):
		return null
	if bp.has_complete_materials():
		return null
	var colonist := actor as Colonist
	if colonist == null:
		return null
	# Carrying any material this blueprint still needs → deliver it. Material-
	# specific (not bare "inventory non-empty") so a future carried tool — or
	# orphan items from a prior failed cleanup — don't send us to deliver
	# pointlessly (deposit_from would take nothing and we'd loop forever).
	if _carries_needed_material(colonist, bp):
		var deliver := JobLeg.new()
		deliver.location = job.location
		deliver.target_node = bp
		deliver.kind = DELIVER
		return deliver
	# Empty (or only carrying non-needed items) → fetch from the nearest crate
	# that holds one of the still-needed materials. No source → give this colonist
	# up for now (null); the job stays available only if a source exists.
	var crate := Colony.storage_registry.find_source(_needed_item_ids(bp), colonist.global_position)
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
## blueprint via the existing Blueprint.deposit_from path.
func complete(actor: Node, leg: JobLeg, job: Job) -> void:
	var bp := job.target_node as Blueprint
	if bp == null or not is_instance_valid(bp):
		return
	if leg.kind == FETCH:
		# Skip if the blueprint was satisfied while we walked here — avoids a
		# pointless withdraw we'd just return in on_end.
		if bp.has_complete_materials():
			return
		var crate_inv := _inventory_of(leg.target_node)
		var colonist := actor as Colonist
		if crate_inv == null or colonist == null or colonist.inventory == null:
			return
		var def := BuildLibrary.get_def(bp.target_def_id)
		if def == null:
			return
		for entry in def.material_cost:
			var remaining: int = entry.count - bp.given_count(entry.item_def.id)
			if remaining <= 0:
				continue
			# transfer_to moves up to `remaining` from the crate into the
			# colonist, clamped by what the crate holds and the colonist's
			# capacity. Live crate stock serializes concurrent haulers.
			crate_inv.transfer_to(colonist.inventory, entry.item_def.id, remaining)
	elif leg.kind == DELIVER:
		# deposit_from takes up to each material's remaining need from the
		# colonist; self-limits, and emits blueprint_materials_ready on the
		# crossing — Colony's single trigger to spawn construction.
		bp.deposit_from(actor)


## On leaving the job (clean finish or abort), return any items still on the
## colonist to the nearest crate so they're not lost or carried into the next
## job. Surplus arises when a parallel hauler satisfied the blueprint while this
## one was mid-fetch, or when a fetch over-drew against a need later filled by
## the player. Items with no home (no crate / all full) stay on the colonist — a
## known minor gap.
func on_end(_success: bool, actor: Node, _leg: JobLeg, _job: Job, _elapsed: float) -> void:
	var colonist := actor as Colonist
	if colonist == null or colonist.inventory == null:
		return
	var crate := Colony.storage_registry.nearest_crate(colonist.global_position)
	var crate_inv := _inventory_of(crate)
	if crate_inv == null:
		return
	for item_id in colonist.inventory.items.keys():
		var count: int = colonist.inventory.get_item_count(item_id)
		if count > 0:
			colonist.inventory.transfer_to(crate_inv, item_id, count)


## A haul job is available while its blueprint exists, is still unsatisfied, and
## some crate holds a still-needed material. The slot half of the gate (colonists
## < max_assignees) lives on Job.is_available; this is the labor-specific half.
func is_available(job: Job) -> bool:
	var bp := job.target_node as Blueprint
	if bp == null or not is_instance_valid(bp):
		return false
	if bp.has_complete_materials():
		return false
	return Colony.storage_registry.has_source_for(_needed_item_ids(bp))


## The item_ids this blueprint still needs (material_cost minus what's deposited).
func _needed_item_ids(bp: Blueprint) -> Array[String]:
	var out: Array[String] = []
	var def := BuildLibrary.get_def(bp.target_def_id)
	if def == null:
		return out
	for entry in def.material_cost:
		if bp.given_count(entry.item_def.id) < entry.count:
			out.append(entry.item_def.id)
	return out


func _carries_needed_material(colonist: Colonist, bp: Blueprint) -> bool:
	if colonist == null or colonist.inventory == null:
		return false
	for id in _needed_item_ids(bp):
		if colonist.inventory.get_item_count(id) > 0:
			return true
	return false


func _inventory_of(node: Node) -> StorageInventory:
	if node == null or not is_instance_valid(node):
		return null
	return node.get_node_or_null("StorageInventory") as StorageInventory
