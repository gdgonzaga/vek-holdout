class_name LootRoller
extends RefCounted
## Pure roll math for LootTable (ARCH loot.md). No state, no signals, no scene
## tree: the caller injects the RandomNumberGenerator so tests can seed it, and
## decides what to do with the result (enemy drops spawn WorldItems).

# =================
# Primary Functions
# =================

## Rolls a table into one merged stack per item id (item_id -> count).
## Guaranteed amounts always land, then every entry rolls independently, so
## there is no cap on how many entries can pass.
static func roll(table: LootTable, rng: RandomNumberGenerator) -> Dictionary[String, int]:
	var result: Dictionary[String, int] = {}
	if table == null:
		return result

	# 1. Guaranteed Amounts: Folding the always-drop list in first so it merges with any matching entry rolls below.
	_add_guaranteed(result, table.guaranteed)

	# 2. Entry Rolls: Rolling each entry independently (chance, then count) so a passing entry never blocks another.
	_add_rolled_entries(result, table.entries, rng)
	return result


# ===================
# Auxiliary Functions
# ===================

static func _add_guaranteed(result: Dictionary[String, int], amounts: Array[ItemAmount]) -> void:
	## Auxiliary: Merges each valid ItemAmount into the result; skips null items and non-positive counts.
	for amount in amounts:
		if amount == null or amount.item_def == null or amount.count <= 0:
			continue
		# 1. Stack Merge: Summing into one stack per item id so the drop spawns a single WorldItem body per item.
		_accumulate(result, amount.item_def.id, amount.count)


static func _add_rolled_entries(result: Dictionary[String, int], entries: Array[LootEntry], rng: RandomNumberGenerator) -> void:
	## Auxiliary: Rolls every entry in order and merges the ones that pass.
	for entry in entries:
		# 1. Entry Roll: Resolving this entry's chance and count; 0 means it did not drop.
		var count: int = _roll_entry(entry, rng)
		if count <= 0:
			continue
		# 2. Stack Merge: Summing into one stack per item id so repeated entries for an item add up.
		_accumulate(result, entry.item_def.id, count)


static func _roll_entry(entry: LootEntry, rng: RandomNumberGenerator) -> int:
	## Auxiliary: Returns the dropped count for one entry, or 0 when it is unusable or its chance roll fails.
	if entry == null or entry.item_def == null:
		return 0

	# 1. Chance Gate: Deciding whether this entry drops at all before spending a count roll on it.
	if not _passes_chance(entry.chance, rng):
		return 0

	# 2. Count Roll: Picking the stack size uniformly within the entry's authored range.
	return _roll_count(entry.min_count, entry.max_count, rng)


static func _passes_chance(chance: float, rng: RandomNumberGenerator) -> bool:
	## Auxiliary: Handles the 0.0 and 1.0 ends explicitly because randf() can return exactly 0.0 or 1.0.
	if chance >= 1.0:
		return true
	if chance <= 0.0:
		return false
	return rng.randf() < chance


static func _roll_count(min_count: int, max_count: int, rng: RandomNumberGenerator) -> int:
	## Auxiliary: Uniform inclusive count; a passing roll never yields less than 1 and max is raised to min.
	var low: int = maxi(min_count, 1)
	var high: int = maxi(max_count, low)
	return rng.randi_range(low, high)


static func _accumulate(result: Dictionary[String, int], item_id: String, count: int) -> void:
	## Auxiliary: Adds count onto the running total for item_id.
	result[item_id] = result.get(item_id, 0) + count
