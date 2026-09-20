class_name GearPickerModel
extends RefCounted
## Pure list model for the Gear sub-tab's item picker: turns the items eligible for a slot
## into filtered, grouped, sorted entries. Holds no state and touches no autoloads; callers
## pass the eligible defs and a stock snapshot so the same logic can be driven from tests
## with in-memory ItemDefs.

## Group label for an item that carries none of the slot's accepted tags. The caller's
## eligibility query should never produce one, but an unlabelled group beats dropping it.
const OTHER_GROUP: String = "Other"

## One picker row's worth of data: the def plus the per-row facts the row scene displays.
class Entry extends RefCounted:
	var def: ItemDef = null
	var group: String = ""
	## Position of the group among the slot's accepted tags; drives group ordering.
	var group_index: int = 0
	## Items held in colony crates (what a fetch job could actually take).
	var stock: int = 0
	var is_target: bool = false
	var is_equipped: bool = false

# =================
# Primary Functions
# =================

## Builds the picker list for one slot.
## accepted_tags is Equipment.SLOT_ACCEPTED_TAGS[slot]; stock_by_id maps item id -> crate stock
## (missing ids count as 0). The current target and equipped item stay visible under the
## In-colony filter so the player never loses sight of what the slot currently wants or wears.
static func build_entries(
		eligible: Array[ItemDef],
		accepted_tags: Array,
		filter_text: String,
		in_colony_only: bool,
		stock_by_id: Dictionary,
		target_id: String,
		equipped_id: String) -> Array[Entry]:
	var clean_filter: String = filter_text.strip_edges().to_lower()
	var entries: Array[Entry] = []

	for def: ItemDef in eligible:
		if def == null:
			continue

		# 1. Text Filter: hide items that do not match the search box so the list shows only what was asked for.
		if not _matches_filter(def, clean_filter):
			continue

		# 2. Entry Snapshot: resolve group, stock and target/equipped flags once so sorting and rows share one view.
		var entry: Entry = _make_entry(def, accepted_tags, stock_by_id, target_id, equipped_id)

		# 3. Colony Filter: drop items the colony cannot supply, except the target and equipped item kept for context.
		if in_colony_only and not _passes_colony_filter(entry):
			continue

		entries.append(entry)

	# 4. Ordering: group by slot tag order, stocked items first, then by name, so rows read top-down by usefulness.
	entries.sort_custom(_is_entry_before)
	return entries

# ===================
# Auxiliary Functions
# ===================

static func _matches_filter(def: ItemDef, clean_filter: String) -> bool:
	## Auxiliary: True when the lowercase filter is empty or appears in the item's name, id or any tag.
	if clean_filter.is_empty():
		return true
	if def.get_display_name().to_lower().contains(clean_filter):
		return true
	if def.id.to_lower().contains(clean_filter):
		return true
	return _any_tag_contains(def, clean_filter)


static func _any_tag_contains(def: ItemDef, clean_filter: String) -> bool:
	## Auxiliary: True if any of the item's tags contains the lowercase filter text.
	for tag: String in def.tags:
		if tag.to_lower().contains(clean_filter):
			return true
	return false


static func _make_entry(
		def: ItemDef,
		accepted_tags: Array,
		stock_by_id: Dictionary,
		target_id: String,
		equipped_id: String) -> Entry:
	## Auxiliary: Packages a def with its group, crate stock and target/equipped flags.
	var entry := Entry.new()
	entry.def = def
	entry.stock = int(stock_by_id.get(def.id, 0))
	entry.is_target = not target_id.is_empty() and def.id == target_id
	entry.is_equipped = not equipped_id.is_empty() and def.id == equipped_id

	# 1. Group Resolution: place the item under its first accepted tag, or the fallback group.
	var tag_index: int = _first_accepted_index(def, accepted_tags)
	entry.group_index = tag_index if tag_index >= 0 else accepted_tags.size()
	entry.group = GearText.group_label(str(accepted_tags[tag_index])) if tag_index >= 0 else OTHER_GROUP
	return entry


static func _first_accepted_index(def: ItemDef, accepted_tags: Array) -> int:
	## Auxiliary: Index of the first accepted tag the item carries, or -1 when it carries none.
	for i: int in accepted_tags.size():
		if def.has_tag(str(accepted_tags[i])):
			return i
	return -1


static func _passes_colony_filter(entry: Entry) -> bool:
	## Auxiliary: In-colony rule: stocked, or the slot's current target, or what the slot is wearing.
	return entry.stock > 0 or entry.is_target or entry.is_equipped


static func _is_entry_before(a: Entry, b: Entry) -> bool:
	## Auxiliary: Sort comparator: group order, then stocked-before-unstocked, then name, then id.
	if a.group_index != b.group_index:
		return a.group_index < b.group_index
	var a_stocked: bool = a.stock > 0
	var b_stocked: bool = b.stock > 0
	if a_stocked != b_stocked:
		return a_stocked
	var name_order: int = a.def.get_display_name().naturalcasecmp_to(b.def.get_display_name())
	if name_order != 0:
		return name_order < 0
	return a.def.id < b.def.id
