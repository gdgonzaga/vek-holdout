extends JobDef
class_name FetchEquipmentJobDef
## Fetch-and-equip labor (ARCH equipment.md).
##
## A FetchEquipmentJob created by this def sends a colonist to a storage crate to
## pick up a specific item and equip it directly into a designated slot — skipping
## the carry-inventory step entirely. The job is targeted (target_colonist_id is set)
## so only the designated colonist can claim it.
##
## Resilience properties:
##   - work_site() re-queries storage every navigation cycle; a destroyed crate
##     causes transparent rerouting to the next available one.
##   - is_available_for() closes the job immediately if desire changed mid-flight
##     or item no longer exists in storage.
##   - complete() equips BEFORE removing from the crate so a failed equip (tag
##     mismatch discovered at runtime) leaves the item safely in storage.
##   - on_abort() is a no-op — the crate was never modified.
##   - FetchEquipmentJob instances are not serialized; the audit regenerates them
##     on the colonist's first claim cycle after a save/load.

## Priority used by JobBoard.get_best_job_for when selecting this def's jobs.
## Beats all normal labor (max ~150), yields to deploy (1000).
const FETCH_EQUIP_PRIORITY: int = 500

# =================
# Primary Functions
# =================

func work_site(actor: Node, job: Variant) -> Variant:
	# Re-query storage every navigation cycle so a destroyed crate causes
	# transparent rerouting rather than a stuck walk target.
	var fetch_job: FetchEquipmentJob = job as FetchEquipmentJob
	if fetch_job == null or not is_instance_valid(actor) or not (actor is Node3D):
		return null

	# Fresh crate lookup from the colonist's current position.
	var crate: Furniture = _find_crate(fetch_job.target_item_id, (actor as Node3D).global_position)
	return crate.global_position if crate != null else null


func is_available_for(job: Variant, actor: Node = null) -> bool:
	var fetch_job: FetchEquipmentJob = job as FetchEquipmentJob
	if fetch_job == null:
		return false

	# Resolve designated colonist — may be null if not yet in scene (editor).
	var colonist: Colonist = _resolve_colonist(fetch_job.target_colonist_id) if actor == null else actor as Colonist

	# Slot already satisfied — nothing to do.
	if colonist != null and colonist.equipment != null:
		var current_in_slot: ItemDef = colonist.equipment.get_item(fetch_job.target_slot)
		if current_in_slot != null and current_in_slot.id == fetch_job.target_item_id:
			return false
		if not fetch_job.is_labor_intercept:
			if colonist.equipment.is_desired_equipped(fetch_job.target_slot):
				return false
			# Desired item changed while job was in flight — this job is stale.
			var current_desired: String = colonist.equipment.get_desired_item(fetch_job.target_slot)
			if current_desired != fetch_job.target_item_id:
				return false

	# Item must exist somewhere in colony storage.
	return _item_in_storage(fetch_job.target_item_id)


func should_close(job: Variant) -> bool:
	var fetch_job: FetchEquipmentJob = job as FetchEquipmentJob
	if fetch_job == null:
		return true

	var colonist: Colonist = _resolve_colonist(fetch_job.target_colonist_id)
	if colonist == null:
		return true

	# Slot is now satisfied (item equipped by any means).
	if colonist.equipment != null:
		var current_item: ItemDef = colonist.equipment.get_item(fetch_job.target_slot)
		if current_item != null and current_item.id == fetch_job.target_item_id:
			return true
		if not fetch_job.is_labor_intercept:
			if colonist.equipment.is_desired_equipped(fetch_job.target_slot):
				return true
			# Desired item changed — this job targets the old desire.
			var current_desired: String = colonist.equipment.get_desired_item(fetch_job.target_slot)
			if current_desired != "" and current_desired != fetch_job.target_item_id:
				return true

	# Item no longer reachable anywhere in colony storage.
	if not _item_in_storage(fetch_job.target_item_id):
		return true

	return false


func meets_requirements(actor: Node, job: Variant) -> bool:
	# Only the designated colonist may claim this job.
	var fetch_job: FetchEquipmentJob = job as FetchEquipmentJob
	if fetch_job == null or fetch_job.target_colonist_id == "":
		return false
	var cid: String = actor.colonist_id if "colonist_id" in actor else ""
	return cid == fetch_job.target_colonist_id


func complete(actor: Node, job: Variant) -> void:
	var fetch_job: FetchEquipmentJob = job as FetchEquipmentJob
	if fetch_job == null or not is_instance_valid(actor):
		return
	var colonist: Colonist = actor as Colonist
	if colonist == null or colonist.equipment == null:
		return

	# 1. Re-resolve storage crate at the moment of completion.
	var crate_pos: Vector3 = (actor as Node3D).global_position if actor is Node3D else Vector3.ZERO
	var crate: Furniture = _find_crate(fetch_job.target_item_id, crate_pos)
	if crate == null:
		return  # Crate gone — job stays alive; next audit reroutes or closes.

	# 2. Verify crate inventory still has the item.
	var crate_inv: Inventory = _crate_inventory(crate)
	if crate_inv == null or not crate_inv.has_item(fetch_job.target_item_id, 1):
		return  # Item gone — job stays alive; should_close() will prune next cycle.

	# 3. Resolve ItemDef. A missing def means a data authoring error; close cleanly.
	var item_def: ItemDef = ItemDB.get_def(fetch_job.target_item_id)
	if item_def == null:
		_finish(actor, job)
		return

	# 4. Verify the slot still accepts this item (tags may have been edited in dev).
	if not colonist.equipment.can_equip_to(fetch_job.target_slot, item_def):
		_finish(actor, job)
		return

	# 5. Handle an occupied slot.
	var current_in_slot: ItemDef = colonist.equipment.get_item(fetch_job.target_slot)
	if current_in_slot != null and current_in_slot.id != fetch_job.target_item_id:
		if fetch_job.is_labor_intercept:
			# For labor intercepts, cascade to holster first then carry inventory.
			if not colonist.equipment.stow_and_equip(fetch_job.target_slot, item_def, colonist.inventory):
				return  # Cannot equip or stow — retry next cycle.
			crate_inv.remove(fetch_job.target_item_id, 1)
			_finish(actor, job)
			return
		else:
			# For loadout fulfillment, unequip directly into carry inventory.
			if not _unequip_slot_to_inventory(colonist, fetch_job.target_slot):
				return  # Carry full — retry next audit cycle.

	# 6. Equip BEFORE removing from crate: if equip somehow fails after the tag
	#    guard above, the item stays safely in storage.
	var equipped: bool = colonist.equipment.equip(fetch_job.target_slot, item_def)
	if not equipped:
		return  # Defensive only.

	# 7. Only now remove the item from the crate.
	crate_inv.remove(fetch_job.target_item_id, 1)
	_finish(actor, job)


func on_abort(_actor: Node, _job: Variant, _elapsed: float) -> void:
	pass  # Crate was never modified; no cleanup needed.


## Factory: build a targeted FetchEquipmentJob for a specific colonist + slot + item.
## Sets target_colonist_id so only the designated colonist can claim it. Caller is
## responsible for adding the returned job to the JobBoard.
static func create_job(
		colonist: Colonist,
		slot_id: String,
		item_id: String,
		def_resource: FetchEquipmentJobDef,
		is_intercept: bool = false) -> FetchEquipmentJob:
	var job := FetchEquipmentJob.new()
	job.id = Tools.generate_uuid()
	job.def = def_resource
	job.labor_id = ""
	job.title = "Fetch Equipment"
	job.max_assignees = 1
	job.target_colonist_id = colonist.colonist_id
	job.target_slot = slot_id
	job.target_item_id = item_id
	job.is_labor_intercept = is_intercept
	# Best-effort initial location for distance scoring in get_best_job_for.
	var crate: Furniture = Colony.storage_registry.find_storage_for(item_id, colonist.global_position) \
			if Colony.storage_registry != null else null
	if crate != null and crate is Node3D:
		job.location = (crate as Node3D).global_position
	return job

# ====================
# Auxiliary Functions
# ====================

func _find_crate(item_id: String, from: Vector3) -> Furniture:
	## Auxiliary: Queries StorageRegistry for the nearest crate containing item_id.
	if Colony == null or Colony.storage_registry == null:
		return null
	return Colony.storage_registry.find_source([item_id], from)


func _crate_inventory(crate: Furniture) -> Inventory:
	## Auxiliary: Returns the StorageInventory of the given crate, or null.
	if crate == null or not is_instance_valid(crate):
		return null
	if Colony.storage_registry == null:
		return null
	return Colony.storage_registry.inventory_of(crate)


func _item_in_storage(item_id: String) -> bool:
	## Auxiliary: True if at least one crate in colony storage contains item_id.
	if Colony == null or Colony.storage_registry == null:
		return false
	return Colony.storage_registry.has_source_for([item_id])


func _resolve_colonist(colonist_id: String) -> Colonist:
	## Auxiliary: Resolves colonist by ID from Colony roster, falling back to scene tree group.
	if colonist_id == "":
		return null
	if Colony != null:
		for c: Colonist in Colony.colonists:
			if is_instance_valid(c) and c.colonist_id == colonist_id:
				return c
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		for node: Node in tree.get_nodes_in_group("colonists"):
			var c := node as Colonist
			if c != null and is_instance_valid(c) and c.colonist_id == colonist_id:
				return c
	return null


func _unequip_slot_to_inventory(colonist: Colonist, slot_id: String) -> bool:
	## Auxiliary: Unequips the item in slot_id into carry inventory if capacity allows.
	##            Returns false (and skips unequip) when carry is full.
	var item: ItemDef = colonist.equipment.get_item(slot_id)
	if item == null:
		return true  # Already empty — nothing to do.
	if colonist.inventory == null or not colonist.inventory.can_add(item.id, 1):
		return false  # Carry full — caller must retry later.
	colonist.equipment.unequip(slot_id)
	colonist.inventory.add(item.id, 1)
	return true
