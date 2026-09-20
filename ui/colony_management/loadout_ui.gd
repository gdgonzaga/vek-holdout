class_name LoadoutUi
extends RefCounted
## Stateless glue shared by the loadout UI (Gear-tab strip and squad card): the result sentences,
## the loadout dropdown rules and the item resolver LoadoutBook.apply_to needs. Kept out of the
## scenes so wording and dropdown behaviour live, and are tested, in one place.

const NO_LOADOUTS_TEXT: String = "(no loadouts)"
const NO_TARGETS_TEXT: String = "No targets set"
const CUSTOM_TARGETS_TEXT: String = "Custom targets"
const NOTHING_TO_DO_TEXT: String = "already up to date"

# =================
# Primary Functions
# =================

## "Applied Miner: 3 changed, 1 skipped (item unavailable)".
static func apply_summary(loadout_name: String, counts: Dictionary) -> String:
	# 1. Count Phrase: the shared "N changed, N skipped" tail, so colonist and squad wording agree.
	var tail: String = _count_phrase(counts)
	return "Applied %s: %s" % [loadout_name, tail]


## "Applied Miner to 3 colonists: 9 changed".
static func squad_apply_summary(loadout_name: String, colonist_count: int, counts: Dictionary) -> String:
	# 1. Count Phrase: the same tail as a single-colonist apply, totalled over the squad.
	var tail: String = _count_phrase(counts)
	var noun: String = "colonist" if colonist_count == 1 else "colonists"
	return "Applied %s to %d %s: %s" % [loadout_name, colonist_count, noun, tail]


## "Saved Miner (5 slots)" for a new loadout, "Updated Miner (1 slot)" for an overwrite.
static func save_summary(loadout_name: String, slot_count: int, overwrote: bool) -> String:
	var verb: String = "Updated" if overwrote else "Saved"
	var noun: String = "slot" if slot_count == 1 else "slots"
	return "%s %s (%d %s)" % [verb, loadout_name, slot_count, noun]


## What the colonist's targets are relative to the saved loadouts.
static func match_text(matching_names: Array[String], has_targets: bool) -> String:
	if not has_targets:
		return NO_TARGETS_TEXT
	if matching_names.is_empty():
		return CUSTOM_TARGETS_TEXT
	return "Matches: %s" % ", ".join(matching_names)


## True when at least one slot has a target, so there is something worth saving as a loadout.
static func has_targets(equipment: Equipment) -> bool:
	if equipment == null:
		return false
	var desired: Dictionary = equipment.get_all_desired_items()
	for slot_id: String in desired:
		if not str(desired[slot_id]).is_empty():
			return true
	return false


## Refills the dropdown from the book, keeping `keep_id` selected when it still exists (otherwise
## the first loadout). An empty book shows a disabled placeholder so the control never looks broken.
static func fill_options(option: OptionButton, book: LoadoutBook, keep_id: String) -> void:
	option.clear()
	var ids: Array[String] = book.list_ids()
	option.disabled = ids.is_empty()
	if ids.is_empty():
		option.add_item(NO_LOADOUTS_TEXT)
		option.select(0)
		return

	# 1. Entries: one item per loadout, carrying its id so renames never break the selection.
	_add_loadout_items(option, book, ids)

	# 2. Selection: keep the player's choice across refreshes instead of snapping back to the top.
	option.select(maxi(ids.find(keep_id), 0))


## The loadout id chosen in the dropdown, or "" for the placeholder / nothing selected.
static func selected_id(option: OptionButton) -> String:
	if option.item_count == 0 or option.selected < 0:
		return ""
	var meta: Variant = option.get_item_metadata(option.selected)
	return meta if meta is String else ""


## Resolver for LoadoutBook.apply_to: the ItemDef for an id, or null when the item no longer exists.
static func item_resolver() -> Callable:
	return Callable(ItemDB, "get_def")

# ===================
# Auxiliary Functions
# ===================

static func _count_phrase(counts: Dictionary) -> String:
	## Auxiliary: "3 changed, 1 skipped (item unavailable)"; zero counts are left out.
	var parts: Array[String] = []
	var changed: int = int(counts.get("changed", 0))
	var skipped: int = int(counts.get("skipped", 0))
	if changed > 0:
		parts.append("%d changed" % changed)
	if skipped > 0:
		parts.append("%d skipped (item unavailable)" % skipped)
	if parts.is_empty():
		return NOTHING_TO_DO_TEXT
	return ", ".join(parts)


static func _add_loadout_items(option: OptionButton, book: LoadoutBook, ids: Array[String]) -> void:
	## Auxiliary: Appends one dropdown item per loadout id, storing the id as item metadata.
	for id: String in ids:
		option.add_item(book.get_name(id))
		option.set_item_metadata(option.item_count - 1, id)
