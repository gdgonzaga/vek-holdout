class_name GearStatus
extends RefCounted
## Pure "why is this slot's target not met yet?" resolver for the Gear sub-tab. Reads the
## colonist, the colony storage registry and the job board through explicit arguments and
## mutates nothing, so the slot rows, the picker's slot-state box and tests all share one
## answer. The resolution order mirrors EquipmentAudit (ARCH equipment.md): partner swap,
## carried, queued fetch, storage. If the audit's order changes, change it here too.

enum State {
	NO_TARGET,
	MET,
	SWAP,
	POCKETS,
	FETCHING,
	IN_STORAGE,
	UNAVAILABLE,
}

## Slots whose items EquipmentAudit can swap in place instead of fetching (hand pair and
## shield pair). Mirrors EquipmentAudit._audit_hand_pair / _audit_shield_pair.
const PARTNER_SLOTS: Dictionary = {
	Equipment.SLOT_MAIN_HAND: Equipment.SLOT_HOLSTER,
	Equipment.SLOT_HOLSTER: Equipment.SLOT_MAIN_HAND,
	Equipment.SLOT_OFF_HAND: Equipment.SLOT_BACK,
	Equipment.SLOT_BACK: Equipment.SLOT_OFF_HAND,
}

const COLOR_MET: Color = Color(0.3, 0.9, 0.3, 1.0)
const COLOR_PENDING: Color = Color(0.9, 0.75, 0.2, 1.0)
const COLOR_BLOCKED: Color = Color(0.9, 0.4, 0.3, 1.0)
const COLOR_MUTED: Color = Color(0.55, 0.55, 0.55, 1.0)

## Outcome for one slot: machine-readable state plus the text and color rows should show.
class Result extends RefCounted:
	var state: GearStatus.State = GearStatus.State.NO_TARGET
	var text: String = ""
	var color: Color = Color.WHITE

	## True while a target is set but not yet equipped (any reason).
	func is_pending() -> bool:
		return state != GearStatus.State.NO_TARGET and state != GearStatus.State.MET

# =================
# Primary Functions
# =================

## Evaluates one slot of `colonist`. A null/freed colonist or a slot with no target reads as
## NO_TARGET so callers can render it without special-casing.
static func evaluate(
		colonist: Colonist,
		slot_id: String,
		registry: StorageRegistry,
		job_board: JobBoard) -> Result:
	if colonist == null or not is_instance_valid(colonist) or colonist.equipment == null:
		# 1. Empty Result: nothing to resolve without a colonist, so show the neutral state.
		return _make_result(State.NO_TARGET, slot_id)

	var target_id: String = colonist.equipment.get_desired_item(slot_id)
	if target_id.is_empty():
		# 2. Empty Result: a slot with no target has no fulfilment story to tell.
		return _make_result(State.NO_TARGET, slot_id)

	# 3. State Resolution: walk the audit's fulfilment order to find the first route that applies.
	var state: State = _resolve_state(colonist, slot_id, target_id, registry, job_board)

	# 4. Presentation: attach the text and color the row and slot-state box display for that state.
	return _make_result(state, slot_id)

# ===================
# Auxiliary Functions
# ===================

static func _resolve_state(
		colonist: Colonist,
		slot_id: String,
		target_id: String,
		registry: StorageRegistry,
		job_board: JobBoard) -> State:
	## Auxiliary: First applicable fulfilment route for a slot that has a target.
	if colonist.equipment.is_desired_equipped(slot_id):
		return State.MET

	# 1. Swap Check: a partner-slot copy is equipped for free, before any walking.
	if _is_in_partner_slot(colonist, slot_id, target_id):
		return State.SWAP

	# 2. Pockets Check: a carried copy is equipped immediately with no job.
	if colonist.inventory != null and colonist.inventory.has_item(target_id, 1):
		return State.POCKETS

	# 3. Queued Fetch Check: a live fetch job means the colonist is already on it.
	if _has_queued_fetch(colonist, slot_id, target_id, job_board):
		return State.FETCHING

	# 4. Storage Check: an unqueued copy in a crate will get a fetch job at the next audit.
	if registry != null and registry.has_source_for([target_id]):
		return State.IN_STORAGE

	return State.UNAVAILABLE


static func _is_in_partner_slot(colonist: Colonist, slot_id: String, target_id: String) -> bool:
	## Auxiliary: True if the swap partner slot holds the target and it may legally move into slot_id.
	if not PARTNER_SLOTS.has(slot_id):
		return false
	var partner_item: ItemDef = colonist.equipment.get_item(PARTNER_SLOTS[slot_id])
	if partner_item == null or partner_item.id != target_id:
		return false
	return colonist.equipment.can_equip_to(slot_id, partner_item)


static func _has_queued_fetch(
		colonist: Colonist, slot_id: String, target_id: String, job_board: JobBoard) -> bool:
	## Auxiliary: True if the board holds a FetchEquipmentJob for this colonist + slot + item.
	if job_board == null:
		return false
	for job: Variant in job_board.get_all_jobs():
		if not (job is FetchEquipmentJob):
			continue
		var fetch: FetchEquipmentJob = job as FetchEquipmentJob
		if fetch.target_colonist_id == colonist.colonist_id \
				and fetch.target_slot == slot_id \
				and fetch.target_item_id == target_id:
			return true
	return false


static func _make_result(state: State, slot_id: String) -> Result:
	## Auxiliary: Packages a state with its display text and color.
	var result := Result.new()
	result.state = state
	result.text = _text_for(state, slot_id)
	result.color = _color_for(state)
	return result


static func _text_for(state: State, slot_id: String) -> String:
	## Auxiliary: Short player-facing reason for a state (the swap reason names the partner slot).
	match state:
		State.MET:
			return "Equipped"
		State.SWAP:
			var partner_name: String = GearText.slot_display_name(str(PARTNER_SLOTS.get(slot_id, "")))
			return "In %s slot: will swap" % partner_name
		State.POCKETS:
			return "In pockets: will equip"
		State.FETCHING:
			return "Fetching from storage"
		State.IN_STORAGE:
			return "In storage: will fetch"
		State.UNAVAILABLE:
			return "None in storage"
		_:
			return "No target"


static func _color_for(state: State) -> Color:
	## Auxiliary: Row/pip color: green when met, amber while the colonist can fix it, red when they cannot.
	match state:
		State.MET:
			return COLOR_MET
		State.SWAP, State.POCKETS, State.FETCHING, State.IN_STORAGE:
			return COLOR_PENDING
		State.UNAVAILABLE:
			return COLOR_BLOCKED
		_:
			return COLOR_MUTED
