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


## Stand-in for "no limit" returned by max_addable for weightless items, which
## capacity cannot constrain. Large enough that no real stack reaches it.
const UNLIMITED_COUNT: int = 1 << 30


## True if `count` of item_id would be accepted right now (known, allowed, and
## within the weight budget). Shares max_addable's rule so it can never disagree
## with what add() actually takes.
func can_add(item_id: String, count: int) -> bool:
	return count <= max_addable(item_id)


## Largest count of item_id this inventory would accept right now: 0 for an
## unknown or filtered-out item or when there is no weight room left, and
## UNLIMITED_COUNT for a weightless item (dividing by its 0 weight would make a
## default-weight ItemDef impossible to carry). Also the cheap "will it fit"
## query UIs use to dim or disable a transfer.
func max_addable(item_id: String) -> int:
	var def := _get_def(item_id)
	if def == null or not is_item_allowed(item_id):
		return 0
	if def.weight <= 0.0:
		return UNLIMITED_COUNT
	var room_by_weight: float = (capacity - current_weight()) / def.weight
	return maxi(0, int(floor(room_by_weight)))


## Adds as many of `count` as fit and returns the overflow (0 when everything
## fit). Emits inventory_changed only when the contents actually changed, so a
## rejected add does not make every open panel rebuild for nothing.
func add(item_id: String, count: int) -> int:
	if count <= 0:
		return 0
	# 1. Room Check: Resolving how many units the weight budget, filter and def lookup allow.
	var to_add := mini(count, max_addable(item_id))
	if to_add <= 0:
		return count
	items[item_id] = items.get(item_id, 0) + to_add
	inventory_changed.emit()
	return count - to_add


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
	return count_items_with_tag(tag) >= count


## Total units, across stacks, of items whose ItemDef carries `tag`. Unknown
## items (no def) never match.
func count_items_with_tag(tag: String) -> int:
	var total := 0
	for item_id in items:
		var def := _get_def(item_id)
		if def != null and def.tags.has(tag):
			total += items[item_id]
	return total


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
## Sizes the move to what the source holds and the target accepts BEFORE
## touching either side, so a rejected or partial transfer never removes and
## re-adds a stack (which reordered the source's item list and fired
## inventory_changed several times mid-transfer). Removes from self first, then
## adds to target, which keeps duplication impossible.
## Returns the number of items that did NOT end up in the target.
func transfer_to(target: Inventory, item_id: String, count: int) -> int:
	# 1. Fit Calculation: Capping the move at what the source has and the target will take.
	var actual := _transferable_count(target, item_id, count)
	if actual <= 0:
		return count

	# Remove from self first
	remove(item_id, actual)

	# Add to target. The pre-check makes a refusal here unexpected, but a target
	# whose add() is stricter than its max_addable() must not swallow items.
	var unplaced := target.add(item_id, actual)
	if unplaced > 0:
		add(item_id, unplaced)

	return count - (actual - unplaced)


func _transferable_count(target: Inventory, item_id: String, count: int) -> int:
	## Auxiliary: The most of `count` that both this inventory holds and `target` accepts.
	return mini(mini(count, get_item_count(item_id)), target.max_addable(item_id))


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
