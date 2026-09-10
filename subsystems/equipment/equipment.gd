class_name Equipment
extends Node
## Per-character 8-slot equipment component. Holds concrete ItemDef references
## keyed by slot ID. Replaces the flat equipped_item: ItemDef pattern on
## Colonist and Player. No visual logic — visuals are owned by EquipmentVisualizer.
## ARCH: equipment.md / GDD §17.

# =============
# Slot Registry
# =============

## Canonical slot IDs — use these constants everywhere rather than raw strings.
const SLOT_HEAD: String = "head"
const SLOT_TORSO: String = "torso"
const SLOT_LEGS: String = "legs"
const SLOT_FEET: String = "feet"
const SLOT_MAIN_HAND: String = "main_hand"
const SLOT_OFF_HAND: String = "off_hand"
const SLOT_HOLSTER: String = "holster"
const SLOT_BACK: String = "back"

## Tags that qualify an item for each slot. An item must carry at least one
## accepted tag to be eligible. Extend this table when new slots are added.
const SLOT_ACCEPTED_TAGS: Dictionary = {
	"head":      ["equip_head"],
	"torso":     ["equip_torso"],
	"legs":      ["equip_legs"],
	"feet":      ["equip_feet"],
	"main_hand": ["tool", "weapon"],
	"off_hand":  ["shield"],
	"holster":   ["tool", "weapon"],
	"back":      ["equip_back", "shield"],
}

# ================
# Primary Functions
# ================

## Emitted whenever a slot's content changes (equip or unequip).
## EquipmentVisualizer listens to this to update 3D meshes.
signal slot_changed(slot_id: String, item: ItemDef)

## Live slot contents. All 8 keys always present; values are ItemDef or null.
var _slots: Dictionary = {
	"head":      null,
	"torso":     null,
	"legs":      null,
	"feet":      null,
	"main_hand": null,
	"off_hand":  null,
	"holster":   null,
	"back":      null,
}


## Returns true if item_def carries at least one tag accepted by slot_id.
func can_equip_to(slot_id: String, item_def: ItemDef) -> bool:
	# Validate slot existence and item presence before tag check.
	return _is_valid_slot_and_item(slot_id, item_def) and _item_matches_slot_tags(slot_id, item_def)


## Places item_def in slot_id. Returns false if the slot or tags are invalid.
## The caller is responsible for removing the item from the character's carry
## inventory before calling this (equipment and inventory are separate stores).
func equip(slot_id: String, item_def: ItemDef) -> bool:
	if not can_equip_to(slot_id, item_def):
		return false
	_slots[slot_id] = item_def
	slot_changed.emit(slot_id, item_def)
	return true


## Removes and returns the item in slot_id, or null if the slot is empty.
## Caller is responsible for returning the item to inventory if needed.
func unequip(slot_id: String) -> ItemDef:
	if not _slots.has(slot_id):
		return null
	var previous: ItemDef = _slots[slot_id]
	_slots[slot_id] = null
	slot_changed.emit(slot_id, null)
	return previous


## Returns the ItemDef currently in slot_id, or null if empty or unknown.
func get_item(slot_id: String) -> ItemDef:
	return _slots.get(slot_id, null)


## Returns true if slot_id is empty (no item equipped).
func is_empty(slot_id: String) -> bool:
	return _slots.get(slot_id, null) == null


## Returns the first valid empty slot for item_def, or "" if none available.
## Prefers main_hand for tool/weapon items to match the active-hand convention.
func get_slot_for_item(item_def: ItemDef) -> String:
	# Prioritize main_hand for tool/weapon items so the first equip lands there.
	var priority_slots: Array[String] = [SLOT_MAIN_HAND, SLOT_HOLSTER]
	for slot_id: String in priority_slots:
		if is_empty(slot_id) and can_equip_to(slot_id, item_def):
			return slot_id
	# Fall back to remaining slots for armor and back items.
	for slot_id: String in SLOT_ACCEPTED_TAGS:
		if slot_id in priority_slots:
			continue
		if is_empty(slot_id) and can_equip_to(slot_id, item_def):
			return slot_id
	return ""


## Returns true if any equipped slot holds an item carrying the given tag.
## Used by BTConditionHasTool to check equipped state before falling back to inventory.
func has_item_with_tag(tag: String) -> bool:
	return _find_slot_with_tag(tag) != ""


## Checks main_hand then holster for needed_tag. Swaps if the needed item is in
## the holster but not the hand. Returns true if the hand now holds the tag.
## Returns false if neither slot has a matching item (caller must fetch from inventory).
func swap_hand_for_tag(needed_tag: StringName) -> bool:
	# Already equipped in the active hand — no swap needed.
	if _hand_already_has_tag(needed_tag):
		return true

	# Holster has the needed item — swap it into the hand.
	if _holster_has_tag(needed_tag):
		_perform_hand_holster_swap()
		return true

	return false


## Unconditionally swaps main_hand <-> holster contents (e.g. sheathing a weapon
## to pull out a work tool, or re-drawing a weapon after work is done).
## Safe when either or both slots are empty.
func swap_hand_to_holster() -> void:
	_perform_hand_holster_swap()


## Snapshot: returns {slot_id: item_def_id} for SaveSystem persistence.
## Empty slots are stored as "" so the key set is always complete.
func serialize() -> Dictionary:
	return _build_serialize_dict()


## Restore from a serialize() dict. Unknown item IDs are silently skipped
## (item was removed from data between saves).
func deserialize(data: Dictionary) -> void:
	_apply_deserialize_dict(data)

# ====================
# Auxiliary Functions
# ====================

func _is_valid_slot_and_item(slot_id: String, item_def: ItemDef) -> bool:
	## Auxiliary: Guards the tag check — slot must exist and item must be non-null.
	return SLOT_ACCEPTED_TAGS.has(slot_id) and item_def != null


func _item_matches_slot_tags(slot_id: String, item_def: ItemDef) -> bool:
	## Auxiliary: Returns true if item_def carries at least one tag from the slot's accepted list.
	var accepted: Array = SLOT_ACCEPTED_TAGS[slot_id]
	for tag: String in accepted:
		if item_def.has_tag(tag):
			return true
	return false


func _find_slot_with_tag(tag: String) -> String:
	## Auxiliary: Linear scan of all slots; returns the first slot ID whose item carries tag.
	for slot_id: String in _slots:
		var item: ItemDef = _slots[slot_id]
		if item != null and item.has_tag(tag):
			return slot_id
	return ""


func _hand_already_has_tag(tag: StringName) -> bool:
	## Auxiliary: True if main_hand currently holds an item with the given tag.
	var hand_item: ItemDef = _slots[SLOT_MAIN_HAND]
	return hand_item != null and hand_item.has_tag(String(tag))


func _holster_has_tag(tag: StringName) -> bool:
	## Auxiliary: True if holster currently holds an item with the given tag.
	var holster_item: ItemDef = _slots[SLOT_HOLSTER]
	return holster_item != null and holster_item.has_tag(String(tag))


func _perform_hand_holster_swap() -> void:
	## Auxiliary: Swaps main_hand and holster contents and emits slot_changed for both.
	var hand_item: ItemDef = _slots[SLOT_MAIN_HAND]
	var holster_item: ItemDef = _slots[SLOT_HOLSTER]
	_slots[SLOT_MAIN_HAND] = holster_item
	_slots[SLOT_HOLSTER] = hand_item
	slot_changed.emit(SLOT_MAIN_HAND, holster_item)
	slot_changed.emit(SLOT_HOLSTER, hand_item)


func _build_serialize_dict() -> Dictionary:
	## Auxiliary: Constructs the {slot_id: item_id} dictionary for save persistence.
	var data: Dictionary = {}
	for slot_id: String in _slots:
		var item: ItemDef = _slots[slot_id]
		data[slot_id] = item.id if item != null else ""
	return data


func _apply_deserialize_dict(data: Dictionary) -> void:
	## Auxiliary: Restores slot contents from a saved dict; unknown IDs become null silently.
	for slot_id: String in _slots:
		var item_id: String = str(data.get(slot_id, ""))
		if item_id != "" and ItemDB.has_def(item_id):
			_slots[slot_id] = ItemDB.get_def(item_id)
		else:
			_slots[slot_id] = null
