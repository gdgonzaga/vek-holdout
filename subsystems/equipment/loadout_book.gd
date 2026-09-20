class_name LoadoutBook
extends RefCounted
## Player-authored equipment loadouts (ARCH equipment.md): named `{slot_id: item_id}` templates
## with at most one item per slot. A loadout is a STAMP, not a link: applying it writes each
## defined slot into the colonist's desired slots through Equipment.set_desired_item and keeps
## no reference, so the audit, fetch jobs and gear status never need to know loadouts exist.
##
## Holds no autoload access. Colony owns the single instance and saves it; callers hand in the
## Equipment to read or write and a resolver for item ids, so tests run on in-memory defs.

## Emitted after any change to the book's contents so open UI can refresh.
signal changed()

## What happened to one slot during apply_to.
enum SlotOutcome { UNCHANGED, CHANGED, SKIPPED }

const ID_PREFIX: String = "loadout_"
const KEY_LOADOUTS: String = "loadouts"
const KEY_NEXT_NUMBER: String = "next_number"
const KEY_NAME: String = "name"
const KEY_SLOTS: String = "slots"

## loadout_id -> {KEY_NAME: String, KEY_SLOTS: {slot_id: item_id}}. Insertion order is creation order.
var _loadouts: Dictionary = {}
## Next id number to hand out. Only ever grows, so a deleted loadout's id is never reused.
var _next_number: int = 1

# =================
# Primary Functions
# =================

## Creates an empty loadout and returns its id, or "" when the name is blank or already used
## (case-insensitive), so the name is a safe key for pickers and overwrite prompts.
func create(display_name: String) -> String:
	# 1. Name Check: a blank or duplicate name would make the picker ambiguous, so refuse it up front.
	var clean_name: String = display_name.strip_edges()
	if not _is_name_available(clean_name, ""):
		return ""

	# 2. Id Allocation: ids are stable across renames and never reused after a delete.
	var id: String = _allocate_id()
	_loadouts[id] = {KEY_NAME: clean_name, KEY_SLOTS: {}}
	changed.emit()
	return id


## Renames a loadout. False when the id is unknown or the name is blank or used by another loadout.
func rename(id: String, display_name: String) -> bool:
	if not _loadouts.has(id):
		return false

	# 1. Name Check: the loadout's own current name does not count as a clash (case-only renames).
	var clean_name: String = display_name.strip_edges()
	if not _is_name_available(clean_name, id):
		return false

	(_loadouts[id] as Dictionary)[KEY_NAME] = clean_name
	changed.emit()
	return true


func delete(id: String) -> void:
	if _loadouts.erase(id):
		changed.emit()


func has(id: String) -> bool:
	return _loadouts.has(id)


## Loadout ids in creation order.
func list_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _loadouts:
		ids.append(id)
	return ids


func get_name(id: String) -> String:
	if not _loadouts.has(id):
		return ""
	return str((_loadouts[id] as Dictionary).get(KEY_NAME, ""))


## The id of the loadout called `display_name` (case-insensitive), or "" when there is none.
func find_id_by_name(display_name: String) -> String:
	var wanted: String = display_name.strip_edges().to_lower()
	for id: String in _loadouts:
		if get_name(id).to_lower() == wanted:
			return id
	return ""


## A copy of the loadout's {slot_id: item_id}, so callers cannot edit the book by accident.
func get_slots(id: String) -> Dictionary:
	if not _loadouts.has(id):
		return {}
	return _slots_of(id).duplicate()


## Sets the one item for a slot. False for an unknown loadout or slot id, or a blank item id
## (use clear_slot to leave a slot undefined).
func set_slot(id: String, slot_id: String, item_id: String) -> bool:
	if not _loadouts.has(id) or not Equipment.SLOT_ACCEPTED_TAGS.has(slot_id) or item_id.is_empty():
		return false
	_slots_of(id)[slot_id] = item_id
	changed.emit()
	return true


## Leaves the slot undefined, so applying the loadout no longer touches it.
func clear_slot(id: String, slot_id: String) -> void:
	if _loadouts.has(id) and _slots_of(id).erase(slot_id):
		changed.emit()


## Replaces the loadout's slots with the colonist's current non-empty targets ("save these
## targets as a loadout"). Empty targets are left undefined instead of stored as blanks.
func capture_from(id: String, equipment: Equipment) -> void:
	if not _loadouts.has(id) or equipment == null:
		return

	# 1. Target Snapshot: keep only slots that actually have a target so apply never writes blanks.
	var captured: Dictionary = _non_empty_targets(equipment)
	(_loadouts[id] as Dictionary)[KEY_SLOTS] = captured
	changed.emit()


## Stamps the loadout onto `equipment`: each defined slot becomes that slot's target. Slots the
## loadout does not define are left alone. `resolve_item` is a Callable(item_id: String) -> ItemDef
## (null when unknown); an item that is unknown or does not fit its slot is skipped, because
## Equipment.set_desired_item only checks the slot id. Returns {"changed": int, "skipped": int}.
func apply_to(id: String, equipment: Equipment, resolve_item: Callable) -> Dictionary:
	var counts: Dictionary = {"changed": 0, "skipped": 0}
	if not _loadouts.has(id) or equipment == null:
		return counts

	var slots: Dictionary = _slots_of(id)
	for slot_id: String in slots:
		# 1. Slot Stamp: validate then write one slot, so a bad item never blocks the rest of the loadout.
		var outcome: SlotOutcome = _apply_slot(equipment, slot_id, str(slots[slot_id]), resolve_item)
		if outcome == SlotOutcome.CHANGED:
			counts["changed"] += 1
		elif outcome == SlotOutcome.SKIPPED:
			counts["skipped"] += 1
	return counts


## True when every slot the loadout defines is already the colonist's target. An empty loadout
## matches nothing, otherwise every colonist would "match" a blank template.
func matches(id: String, equipment: Equipment) -> bool:
	if not _loadouts.has(id) or equipment == null:
		return false

	var slots: Dictionary = _slots_of(id)
	if slots.is_empty():
		return false
	for slot_id: String in slots:
		if equipment.get_desired_item(slot_id) != str(slots[slot_id]):
			return false
	return true


## Ids of every loadout the colonist's targets currently match, in creation order.
func find_matching_ids(equipment: Equipment) -> Array[String]:
	var found: Array[String] = []
	for id: String in _loadouts:
		# 1. Match Test: reuse the single-loadout rule so the label and the check never disagree.
		if matches(id, equipment):
			found.append(id)
	return found


## SaveSystem contract: plain dictionaries and strings only, safe to round-trip through JSON.
func serialize() -> Dictionary:
	return {
		KEY_LOADOUTS: _loadouts.duplicate(true),
		KEY_NEXT_NUMBER: _next_number,
	}


## Restores from serialize(). Replaces current contents; tolerates missing or malformed data
## (older saves have no loadouts at all) by dropping what it cannot read.
func deserialize(data: Dictionary) -> void:
	_loadouts.clear()

	# 1. Entry Restore: rebuild each loadout from sanitized data so a bad entry cannot poison the book.
	var raw_loadouts: Variant = data.get(KEY_LOADOUTS, {})
	if raw_loadouts is Dictionary:
		_restore_entries(raw_loadouts as Dictionary)

	# 2. Id Counter: resume past every restored id so new loadouts never collide with old ones.
	_next_number = _resume_number(data.get(KEY_NEXT_NUMBER, 1))
	changed.emit()


## Forgets every loadout (New Game).
func reset() -> void:
	_loadouts.clear()
	_next_number = 1
	changed.emit()

# ===================
# Auxiliary Functions
# ===================

func _slots_of(id: String) -> Dictionary:
	## Auxiliary: The loadout's live {slot_id: item_id} dictionary (callers must check has(id) first).
	return (_loadouts[id] as Dictionary)[KEY_SLOTS] as Dictionary


func _is_name_available(clean_name: String, ignore_id: String) -> bool:
	## Auxiliary: A non-blank name that no other loadout (ignoring `ignore_id`) already uses, case-insensitive.
	if clean_name.is_empty():
		return false
	var lowered: String = clean_name.to_lower()
	for id: String in _loadouts:
		if id != ignore_id and get_name(id).to_lower() == lowered:
			return false
	return true


func _allocate_id() -> String:
	## Auxiliary: The next unused "loadout_N" id; the loop only matters for hand-edited saves.
	var id: String = "%s%d" % [ID_PREFIX, _next_number]
	_next_number += 1
	while _loadouts.has(id):
		id = "%s%d" % [ID_PREFIX, _next_number]
		_next_number += 1
	return id


func _non_empty_targets(equipment: Equipment) -> Dictionary:
	## Auxiliary: The colonist's {slot_id: item_id} targets with the blank ("no target") slots dropped.
	var targets: Dictionary = {}
	var desired: Dictionary = equipment.get_all_desired_items()
	for slot_id: String in desired:
		var item_id: String = str(desired[slot_id])
		if not item_id.is_empty():
			targets[slot_id] = item_id
	return targets


func _apply_slot(
		equipment: Equipment, slot_id: String, item_id: String, resolve_item: Callable) -> SlotOutcome:
	## Auxiliary: Validates one slot's item, then makes it the target unless it already is.
	var item: ItemDef = resolve_item.call(item_id) as ItemDef
	if item == null or not equipment.can_equip_to(slot_id, item):
		return SlotOutcome.SKIPPED
	if equipment.get_desired_item(slot_id) == item_id:
		return SlotOutcome.UNCHANGED
	equipment.set_desired_item(slot_id, item_id)
	return SlotOutcome.CHANGED


func _restore_entries(raw_loadouts: Dictionary) -> void:
	## Auxiliary: Loads every readable {name, slots} entry; entries that are not dictionaries are dropped.
	for raw_id: Variant in raw_loadouts:
		var entry: Variant = raw_loadouts[raw_id]
		if not entry is Dictionary:
			continue
		var id: String = str(raw_id)
		# A missing name falls back to the id so the slots are not lost with it.
		var saved_name: String = str((entry as Dictionary).get(KEY_NAME, "")).strip_edges()
		_loadouts[id] = {
			KEY_NAME: saved_name if not saved_name.is_empty() else id,
			KEY_SLOTS: _sanitize_slots((entry as Dictionary).get(KEY_SLOTS, {})),
		}


func _sanitize_slots(raw_slots: Variant) -> Dictionary:
	## Auxiliary: Only known slot ids with a non-blank item id survive a load.
	var clean: Dictionary = {}
	if not raw_slots is Dictionary:
		return clean
	for slot_id: Variant in raw_slots:
		var item_id: String = str((raw_slots as Dictionary)[slot_id])
		if Equipment.SLOT_ACCEPTED_TAGS.has(str(slot_id)) and not item_id.is_empty():
			clean[str(slot_id)] = item_id
	return clean


func _resume_number(saved_number: Variant) -> int:
	## Auxiliary: An id counter above both the saved counter and every restored "loadout_N" id.
	var resume: int = 1
	if typeof(saved_number) == TYPE_INT or typeof(saved_number) == TYPE_FLOAT:
		resume = maxi(resume, int(saved_number))
	for id: String in _loadouts:
		var suffix: String = id.trim_prefix(ID_PREFIX)
		if id.begins_with(ID_PREFIX) and suffix.is_valid_int():
			resume = maxi(resume, suffix.to_int() + 1)
	return resume
