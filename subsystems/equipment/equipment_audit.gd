class_name EquipmentAudit
## Static helpers for colonist equipment fulfillment (ARCH equipment.md).
##
## Shared by BTActionClaimJob (runs at every job-claim boundary) and JobBoard
## (runs in the idle fallback when no labor is available). All methods are static
## so no scene node is required and there is no instance state.
##
## Audit trigger points:
##   1. BTActionClaimJob._cleanup_incompatible_held_items → EquipmentAudit.run_audit()
##   2. JobBoard.get_best_job_for (idle fallback)        → EquipmentAudit.run_audit()
##
## Slot-pair processing order ensures swap resolution happens before any fetch job
## is posted — if the desired item is already on the colonist's body in the partner
## slot, a swap is free and no walk is needed:
##   1. main_hand + holster (sidearm) pair
##   2. off_hand + back pair
##   3. head, torso, legs, feet — independent

## Preloaded singleton def so all callers share one resource object.
const FETCH_EQUIP_DEF: FetchEquipmentJobDef = preload("res://data/jobs/fetch_equipment.tres")

# =================
# Primary Functions
# =================

## Entry point. Processes all 8 slots for colonist, posting FetchEquipmentJob
## instances or performing free in-place equips as appropriate.
static func run_audit(colonist: Colonist, job_board: JobBoard) -> void:
	if colonist == null or not is_instance_valid(colonist):
		return
	if colonist.equipment == null or job_board == null:
		return

	# 1. main_hand + holster (sidearm): resolve swaps first to avoid unnecessary fetches.
	_audit_hand_pair(colonist, job_board)

	# 2. off_hand + back: same swap-first logic for shield-class items.
	_audit_shield_pair(colonist, job_board)

	# 3. Armor slots: fully independent — no swap partner exists.
	_audit_single_slot(colonist, Equipment.SLOT_HEAD, job_board)
	_audit_single_slot(colonist, Equipment.SLOT_TORSO, job_board)
	_audit_single_slot(colonist, Equipment.SLOT_LEGS, job_board)
	_audit_single_slot(colonist, Equipment.SLOT_FEET, job_board)

# ====================
# Auxiliary Functions
# ====================

static func _audit_hand_pair(colonist: Colonist, job_board: JobBoard) -> void:
	## Auxiliary: Audits main_hand and holster (sidearm) together.
	##            A swap satisfies both slots in one call when the desired item
	##            is already equipped in the partner slot.
	var desired_hand: String = colonist.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)
	var desired_holster: String = colonist.equipment.get_desired_item(Equipment.SLOT_HOLSTER)
	var hand_item: ItemDef = colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND)
	var holster_item: ItemDef = colonist.equipment.get_item(Equipment.SLOT_HOLSTER)

	# Desired main_hand item is currently in the holster — swap resolves both slots.
	if desired_hand != "" and holster_item != null and holster_item.id == desired_hand:
		colonist.equipment.swap_hand_to_holster()
		# Re-read after swap for individual slot checks below.
		hand_item = colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND)
		holster_item = colonist.equipment.get_item(Equipment.SLOT_HOLSTER)

	# Desired sidearm item is currently in main_hand — swap resolves both slots.
	elif desired_holster != "" and hand_item != null and hand_item.id == desired_holster:
		colonist.equipment.swap_hand_to_holster()
		hand_item = colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND)
		holster_item = colonist.equipment.get_item(Equipment.SLOT_HOLSTER)

	# Audit each slot independently for remaining unsatisfied state.
	_audit_single_slot(colonist, Equipment.SLOT_MAIN_HAND, job_board)
	_audit_single_slot(colonist, Equipment.SLOT_HOLSTER, job_board)


static func _audit_shield_pair(colonist: Colonist, job_board: JobBoard) -> void:
	## Auxiliary: Audits off_hand and back together. Both accept the "shield" tag
	##            so a shield in the wrong slot can be swapped without fetching.
	var desired_off: String = colonist.equipment.get_desired_item(Equipment.SLOT_OFF_HAND)
	var desired_back: String = colonist.equipment.get_desired_item(Equipment.SLOT_BACK)
	var off_item: ItemDef = colonist.equipment.get_item(Equipment.SLOT_OFF_HAND)
	var back_item: ItemDef = colonist.equipment.get_item(Equipment.SLOT_BACK)

	# Desired off_hand item is in back and the back item can go in off_hand — swap.
	if desired_off != "" and back_item != null and back_item.id == desired_off:
		if colonist.equipment.can_equip_to(Equipment.SLOT_OFF_HAND, back_item):
			_swap_off_back(colonist)
			off_item = colonist.equipment.get_item(Equipment.SLOT_OFF_HAND)
			back_item = colonist.equipment.get_item(Equipment.SLOT_BACK)

	# Desired back item is in off_hand and the off_hand item can go in back — swap.
	elif desired_back != "" and off_item != null and off_item.id == desired_back:
		if colonist.equipment.can_equip_to(Equipment.SLOT_BACK, off_item):
			_swap_off_back(colonist)
			off_item = colonist.equipment.get_item(Equipment.SLOT_OFF_HAND)
			back_item = colonist.equipment.get_item(Equipment.SLOT_BACK)

	# Audit each slot independently for remaining unsatisfied state.
	_audit_single_slot(colonist, Equipment.SLOT_OFF_HAND, job_board)
	_audit_single_slot(colonist, Equipment.SLOT_BACK, job_board)


static func _audit_single_slot(
		colonist: Colonist, slot_id: String, job_board: JobBoard) -> void:
	## Auxiliary: Audits one slot. Steps:
	##   1. Skip if no desired item is set for this slot.
	##   2. Skip if slot is already satisfied.
	##   3. Unequip wrong item into carry inventory (skip if carry full).
	##   4. Equip from carry inventory immediately if item is already carried.
	##   5. Skip if a valid fetch job for this slot+item already exists on the board.
	##   6. Post a FetchEquipmentJob if the item is in colony storage.
	var desired_id: String = colonist.equipment.get_desired_item(slot_id)
	if desired_id == "":
		return

	# Already satisfied — nothing to do this cycle.
	if colonist.equipment.is_desired_equipped(slot_id):
		return

	# Wrong item occupies the slot — try to unequip it into carry inventory.
	var current: ItemDef = colonist.equipment.get_item(slot_id)
	if current != null and current.id != desired_id:
		# Returns false when carry is full; audit continues and posts fetch anyway
		# so the correct item arrives while the colonist clears carry via hygiene.
		_unequip_to_inventory(colonist, slot_id)

	# Desired item is already in carry inventory — equip it immediately, no job needed.
	if _equip_from_inventory(colonist, slot_id, desired_id):
		return

	# A valid fetch job already targets this colonist + slot + item — no duplicate.
	if _fetch_job_exists(colonist, slot_id, desired_id, job_board):
		return

	# Item exists in storage — post a fetch job.
	if _item_in_storage(desired_id):
		_post_fetch_job(colonist, slot_id, desired_id, job_board)


static func _unequip_to_inventory(colonist: Colonist, slot_id: String) -> bool:
	## Auxiliary: Unequips the item in slot_id into carry inventory if capacity allows.
	##            Returns false (skips unequip) when carry is full — caller continues.
	var item: ItemDef = colonist.equipment.get_item(slot_id)
	if item == null:
		return true
	if colonist.inventory == null or not colonist.inventory.can_add(item.id, 1):
		return false
	colonist.equipment.unequip(slot_id)
	colonist.inventory.add(item.id, 1)
	return true


static func _equip_from_inventory(
		colonist: Colonist, slot_id: String, item_id: String) -> bool:
	## Auxiliary: If the desired item is in carry inventory, removes it and equips it
	##            directly — no fetch job or navigation required. Returns true on success.
	if colonist.inventory == null or not colonist.inventory.has_item(item_id, 1):
		return false
	var item_def: ItemDef = ItemDB.get_def(item_id)
	if item_def == null:
		return false
	if not colonist.equipment.can_equip_to(slot_id, item_def):
		return false
	colonist.inventory.remove(item_id, 1)
	return colonist.equipment.equip(slot_id, item_def)


static func _fetch_job_exists(
		colonist: Colonist, slot_id: String, item_id: String, job_board: JobBoard) -> bool:
	## Auxiliary: Returns true if a live FetchEquipmentJob already exists on the board
	##            targeting this colonist, slot, AND item_id.
	##            A job for the same slot but a different item_id is treated as absent
	##            (stale — should_close() will prune it next prune pass).
	for job: Variant in job_board.get_all_jobs():
		if not (job is FetchEquipmentJob):
			continue
		var fj: FetchEquipmentJob = job as FetchEquipmentJob
		if fj.target_colonist_id == colonist.colonist_id \
				and fj.target_slot == slot_id \
				and fj.target_item_id == item_id:
			return true
	return false


static func _post_fetch_job(
		colonist: Colonist, slot_id: String, item_id: String, job_board: JobBoard) -> void:
	## Auxiliary: Creates and registers a targeted FetchEquipmentJob for this colonist.
	var job: FetchEquipmentJob = FetchEquipmentJobDef.create_job(colonist, slot_id, item_id, FETCH_EQUIP_DEF)
	job_board.add_job(job)


static func _item_in_storage(item_id: String) -> bool:
	## Auxiliary: True if at least one crate in colony storage contains item_id.
	if Colony == null or Colony.storage_registry == null:
		return false
	return Colony.storage_registry.find_storage_for(item_id, Vector3.ZERO) != null


static func _swap_off_back(colonist: Colonist) -> void:
	## Auxiliary: Unconditionally swaps off_hand and back contents, emitting
	##            slot_changed for both so EquipmentVisualizer updates correctly.
	var off: ItemDef = colonist.equipment.get_item(Equipment.SLOT_OFF_HAND)
	var back: ItemDef = colonist.equipment.get_item(Equipment.SLOT_BACK)
	# Use unequip/equip pairs so slot_changed fires for both slots.
	colonist.equipment.unequip(Equipment.SLOT_OFF_HAND)
	colonist.equipment.unequip(Equipment.SLOT_BACK)
	if back != null:
		colonist.equipment.equip(Equipment.SLOT_OFF_HAND, back)
	if off != null:
		colonist.equipment.equip(Equipment.SLOT_BACK, off)
