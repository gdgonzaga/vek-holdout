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

## Emitted whenever a slot's desired target item changes.
signal desired_slot_changed(slot_id: String, item_id: String)

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

## Desired target item ID for each slot. All 8 keys present; values are item_id or "".
var _desired_slots: Dictionary = {
	"head":      "",
	"torso":     "",
	"legs":      "",
	"feet":      "",
	"main_hand": "",
	"off_hand":  "",
	"holster":   "",
	"back":      "",
}


## Ensures actor has an Equipment component and its paired EquipmentVisualizer,
## wired via slot_changed. `current` is the actor's already-resolved Equipment
## (if any) — pass the actor's own field so a pre-existing component is kept
## instead of replaced. Returns the resolved Equipment. Shared by Player and
## Colonist _ready (ARCH equipment.md).
static func ensure_on(actor: Node, current: Equipment = null) -> Equipment:
	var eq := current
	if eq == null:
		eq = Equipment.new()
		eq.name = "Equipment"
		actor.add_child(eq)

	# 1. Visualizer Wiring: Creates the sibling EquipmentVisualizer (if missing) and connects slot_changed.
	_ensure_visualizer(eq, actor)
	return eq


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


## Equips item_def into slot_id, displacing any existing item to holster (if empty)
## or carry inventory if holster is occupied or ineligible.
func stow_and_equip(slot_id: String, item_def: ItemDef, inventory: Inventory = null) -> bool:
	if not can_equip_to(slot_id, item_def):
		return false
	var current: ItemDef = get_item(slot_id)
	if current == null:
		return equip(slot_id, item_def)
	if current.id == item_def.id:
		return true

	# 1. Holster Displacement: Attempting to stow the held item into the holster slot first.
	if _try_stow_to_holster(slot_id, current):
		return equip(slot_id, item_def)

	# 2. Inventory Displacement: Stashing the held item into carry inventory if capacity allows.
	if _try_stow_to_inventory(slot_id, current, inventory):
		return equip(slot_id, item_def)

	return false


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


## Equips item_def into main_hand, falling back to the first other valid slot
## (via get_slot_for_item) if main_hand can't accept it. Returns false if no
## slot is eligible. Shared main-hand-first equip policy for Player/Colonist.
func equip_preferring_main_hand(item_def: ItemDef) -> bool:
	var slot: String = SLOT_MAIN_HAND
	if not can_equip_to(slot, item_def):
		slot = get_slot_for_item(item_def)
	if slot.is_empty():
		return false
	return equip(slot, item_def)


## Returns true if any equipped slot holds an item carrying the given tag.
## Used by BTConditionHasTool to check equipped state before falling back to inventory.
func has_item_with_tag(tag: String) -> bool:
	return _find_slot_with_tag(tag) != ""


## Returns true if any equipped slot holds the specific item ID or an item with any of the tags.
func has_required_equipment(item_id: String, tags: Array[StringName]) -> bool:
	# 1. Item ID Evaluation: Checking exact item ID across all equipped slots.
	if item_id != "" and _has_equipped_item_id(item_id):
		return true

	# 2. Tag Evaluation: Checking if any slot holds an item matching any requested tag.
	if not tags.is_empty() and _has_any_equipped_tag(tags):
		return true

	return false


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


## Swaps main_hand and holster if the requested item ID or tag is in the holster.
## Returns true if main_hand now holds a matching item, false otherwise.
func swap_hand_for_requirements(item_id: String, tags: Array[StringName]) -> bool:
	# 1. Active Hand Evaluation: Check if main_hand already satisfies the requirements.
	if _slot_matches_requirements(SLOT_MAIN_HAND, item_id, tags):
		return true

	# 2. Holster Evaluation: Check if holster satisfies requirements and swap to main_hand.
	if _slot_matches_requirements(SLOT_HOLSTER, item_id, tags):
		_perform_hand_holster_swap()
		return true

	return false


## Unconditionally swaps main_hand <-> holster contents (e.g. sheathing a weapon
## to pull out a work tool, or re-drawing a weapon after work is done).
## Safe when either or both slots are empty.
func swap_hand_to_holster() -> void:
	_perform_hand_holster_swap()


## Returns the desired item ID for slot_id ("" if none).
func get_desired_item(slot_id: String) -> String:
	return _desired_slots.get(slot_id, "")


## Sets the desired item ID for slot_id.
func set_desired_item(slot_id: String, item_id: String) -> void:
	if not SLOT_ACCEPTED_TAGS.has(slot_id):
		return
	_desired_slots[slot_id] = item_id
	desired_slot_changed.emit(slot_id, item_id)


## Clears the desired item for slot_id.
func clear_desired_item(slot_id: String) -> void:
	set_desired_item(slot_id, "")


## Returns a copy of the desired slots dictionary.
func get_all_desired_items() -> Dictionary:
	return _desired_slots.duplicate()


## Returns true if the desired item is currently equipped in slot_id.
## If no item is desired (""), returns true only if the slot is empty.
func is_desired_equipped(slot_id: String) -> bool:
	var desired: String = get_desired_item(slot_id)
	var current: ItemDef = get_item(slot_id)
	if desired.is_empty():
		return current == null
	return current != null and current.id == desired


## Static domain helper: queries ItemDB and returns all ItemDefs that can be equipped to slot_id.
static func get_eligible_items_for_slot(slot_id: String) -> Array[ItemDef]:
	var eligible: Array[ItemDef] = []
	if not SLOT_ACCEPTED_TAGS.has(slot_id):
		return eligible
	var accepted: Array = SLOT_ACCEPTED_TAGS[slot_id]
	for item_def: ItemDef in ItemDB.get_all_defs():
		if item_def == null:
			continue
		for tag: String in accepted:
			if item_def.has_tag(tag):
				eligible.append(item_def)
				break
	return eligible


## Snapshot: returns {slot_id: item_def_id} along with "_desired" dictionary for SaveSystem persistence.
## Empty slots are stored as "" so the key set is always complete.
func serialize() -> Dictionary:
	var data: Dictionary = _build_serialize_dict()
	data["_desired"] = _desired_slots.duplicate()
	return data


## Restore from a serialize() dict. Unknown item IDs are silently skipped.
func deserialize(data: Dictionary) -> void:
	_apply_deserialize_dict(data)
	if data.has("_desired") and data["_desired"] is Dictionary:
		_apply_deserialize_desired_dict(data["_desired"])
	elif data.has("desired") and data["desired"] is Dictionary:
		_apply_deserialize_desired_dict(data["desired"])
	else:
		_reset_desired_slots()

# ====================
# Auxiliary Functions
# ====================

static func _ensure_visualizer(equipment: Equipment, actor: Node) -> void:
	## Auxiliary: Creates actor's EquipmentVisualizer child if missing and connects it to slot_changed once.
	var vis := actor.get_node_or_null("EquipmentVisualizer") as EquipmentVisualizer
	if vis == null:
		vis = EquipmentVisualizer.new()
		vis.name = "EquipmentVisualizer"
		actor.add_child(vis)
	if not equipment.slot_changed.is_connected(vis.on_slot_changed):
		equipment.slot_changed.connect(vis.on_slot_changed)


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


func _has_equipped_item_id(item_id: String) -> bool:
	## Auxiliary: Checks if any slot holds an item with the given ID.
	for slot_id: String in _slots:
		var item: ItemDef = _slots[slot_id]
		if item != null and item.id == item_id:
			return true
	return false


func _has_any_equipped_tag(tags: Array[StringName]) -> bool:
	## Auxiliary: Checks if any slot holds an item carrying at least one of the tags.
	for tag: StringName in tags:
		if tag != &"" and _find_slot_with_tag(String(tag)) != "":
			return true
	return false


func _slot_matches_requirements(slot_id: String, item_id: String, tags: Array[StringName]) -> bool:
	## Auxiliary: Checks if the specified slot holds an item matching item_id or any of tags.
	var item: ItemDef = _slots.get(slot_id, null)
	if item == null:
		return false
	if item_id != "" and item.id == item_id:
		return true
	for tag: StringName in tags:
		if tag != &"" and item.has_tag(String(tag)):
			return true
	return false


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


func _try_stow_to_holster(slot_id: String, current_item: ItemDef) -> bool:
	## Auxiliary: Moves item from slot_id to holster if slot is main_hand, holster is empty, and accepts the item.
	if slot_id != SLOT_MAIN_HAND or not is_empty(SLOT_HOLSTER):
		return false
	if not can_equip_to(SLOT_HOLSTER, current_item):
		return false
	unequip(slot_id)
	equip(SLOT_HOLSTER, current_item)
	return true


func _try_stow_to_inventory(slot_id: String, current_item: ItemDef, inventory: Inventory) -> bool:
	## Auxiliary: Unequips item from slot_id and places it into the provided carry inventory.
	if inventory == null or not inventory.can_add(current_item.id, 1):
		return false
	unequip(slot_id)
	inventory.add(current_item.id, 1)
	return true


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


func _apply_deserialize_desired_dict(desired_data: Dictionary) -> void:
	## Auxiliary: Restores desired slot assignments from saved dictionary.
	for slot_id: String in _desired_slots:
		_desired_slots[slot_id] = str(desired_data.get(slot_id, ""))


func _reset_desired_slots() -> void:
	## Auxiliary: Clears all desired slot assignments to empty strings.
	for slot_id: String in _desired_slots:
		_desired_slots[slot_id] = ""
