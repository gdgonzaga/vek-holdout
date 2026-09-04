class_name Inventory
extends Node

## Maximum carry weight for this inventory. Set by child classes.
var capacity: float = 0.0
## Stored items: { item_id (String): count (int) }
var items: Dictionary = {}

signal inventory_changed()


## Virtual check: whether this inventory is allowed to store item_id.
## Base inventory allows all items. Subclasses (e.g. StorageInventory) override
## this to enforce item/tag restrictions.
func is_item_allowed(_item_id: String) -> bool:
	return true


func can_add(item_id: String, count: int) -> bool:
	var def := _get_def(item_id)
	if def == null or not is_item_allowed(item_id):
		return false
	return current_weight() + (count * def.weight) <= capacity


func add(item_id: String, count: int) -> int:
	if count <= 0:
		return 0
	var def := _get_def(item_id)
	if def == null:
		return count  # unknown item, treat all as overflow
	if not is_item_allowed(item_id):
		return count  # disallowed item, reject all

	var added := 0
	var remaining := count

	while remaining > 0:
		var space_by_weight : float = (capacity - current_weight()) / def.weight
		var can_take := mini(remaining, int(floor(space_by_weight)))
		if can_take <= 0:
			break
		items[item_id] = items.get(item_id, 0) + can_take
		added += can_take
		remaining -= can_take

	inventory_changed.emit()
	return remaining


func remove(item_id: String, count: int) -> int:
	if count <= 0:
		return 0
	var current: int = items.get(item_id, 0)
	var to_remove := mini(count, current)

	if to_remove <= 0:
		return count

	if to_remove == current:
		items.erase(item_id)
	else:
		items[item_id] = current - to_remove

	inventory_changed.emit()
	return count - to_remove


func has_item(item_id: String, count: int) -> bool:
	return items.get(item_id, 0) >= count


## True if items whose ItemDef carries `tag` total at least `count` across
## stacks (e.g. any carried "tool"). Unknown items (no def) never match.
func has_item_tag(tag: String, count: int = 1) -> bool:
	var total := 0
	for item_id in items:
		var def := _get_def(item_id)
		if def != null and def.tags.has(tag):
			total += items[item_id]
			if total >= count:
				return true
	return false


func get_item_count(item_id: String) -> int:
	return items.get(item_id, 0)


func current_weight() -> float:
	var total := 0.0
	for item_id in items:
		var def := _get_def(item_id)
		if def:
			total += items[item_id] * def.weight
	return total


## Transfer items from this inventory to the target.
## Removes from self first, then adds to target.
## Returns the number of items that did NOT end up in the target.
func transfer_to(target: Inventory, item_id: String, count: int) -> int:
	var actual := mini(count, get_item_count(item_id))
	if actual <= 0:
		return count

	# Remove from self first
	remove(item_id, actual)

	# Add to target; anything that doesn't fit goes back to self
	var unplaced := target.add(item_id, actual)
	if unplaced > 0:
		add(item_id, unplaced)

	return count - (actual - unplaced)


func _get_def(item_id: String) -> ItemDef:
	return ItemDB.get_def(item_id)


# --- SaveSystem contract -----------------------------------------------------
# Inherited by CharacterInventory (player carry) and StorageInventory (crate /
# shelf contents). Capacity is config/equipment-derived, not persisted here:
# only the item stacks are run state.

## Snapshot the item stacks: {item_id (String): count (int)}.
func serialize() -> Dictionary:
	return {"items": items.duplicate(true)}


## Restore item stacks from a serialize() dict. Re-emits inventory_changed so
## any subscribed UI refreshes. Defensive: missing/empty data yields an empty
## inventory.
func deserialize(data: Dictionary) -> void:
	items.clear()
	var saved: Dictionary = data.get("items", {})
	for item_id in saved:
		items[item_id] = int(saved[item_id])
	inventory_changed.emit()
