class_name StorageSummary
extends RefCounted
## Pure one-line description of a container for the transfer panel header:
## "Priority 3 - Accepts anything" / "Priority 2 - Accepts: Plank, Stone +2 more".
## StorageInventory.is_item_allowed admits an item that matches EITHER the item
## whitelist OR a tag, so both are shown when both are set.

## Names listed before the rest are folded into "+N more".
const _MAX_LISTED: int = 3


# =================
# Primary Functions
# =================

## "Priority N - <filter text>" for a container.
static func describe(storage: StorageInventory) -> String:
	return "%s - %s" % [priority_text(storage.priority), filter_text(storage.allowed_item_ids, storage.allowed_tags)]


static func priority_text(priority: int) -> String:
	return "Priority %d" % priority


## What a container accepts: anything, or the whitelisted items and/or tags.
static func filter_text(allowed_item_ids: Array[String], allowed_tags: Array[String]) -> String:
	if allowed_item_ids.is_empty() and allowed_tags.is_empty():
		return "Accepts anything"
	# 1. Item Whitelist: Display names, cut after a few so the header stays one line.
	var parts: Array[String] = []
	if not allowed_item_ids.is_empty():
		parts.append("Accepts: %s" % _join_limited(_display_names(allowed_item_ids)))
	# 2. Tag Rule: Shown alongside the items because either one admits an item.
	if not allowed_tags.is_empty():
		var tag_label: String = "tagged: %s" if not parts.is_empty() else "Accepts tagged: %s"
		parts.append(tag_label % ", ".join(allowed_tags))
	return "; ".join(parts)


## Filter panel status line. Counts the whitelist AND names the tag rule, so a
## container limited only by a tag is never called "Unrestricted".
static func status_text(allowed_item_ids: Array[String], allowed_tags: Array[String]) -> String:
	if allowed_item_ids.is_empty() and allowed_tags.is_empty():
		return "Status: Unrestricted (accepts all items)"
	var parts: Array[String] = []
	if not allowed_item_ids.is_empty():
		parts.append("%d item%s allowed" % [allowed_item_ids.size(), "" if allowed_item_ids.size() == 1 else "s"])
	if not allowed_tags.is_empty():
		parts.append("tagged: %s" % ", ".join(allowed_tags))
	return "Status: Restricted (%s)" % "; ".join(parts)


# ===================
# Auxiliary Functions
# ===================

static func _display_names(item_ids: Array[String]) -> Array[String]:
	## Auxiliary: Display names for ids, falling back to the raw id for a removed item.
	var names: Array[String] = []
	for item_id: String in item_ids:
		names.append(ItemDB.get_display_name(item_id))
	return names


static func _join_limited(names: Array[String]) -> String:
	## Auxiliary: Comma list of the first few names, then "+N more" for the rest.
	if names.size() <= _MAX_LISTED:
		return ", ".join(names)
	var listed: Array[String] = names.slice(0, _MAX_LISTED)
	return "%s +%d more" % [", ".join(listed), names.size() - _MAX_LISTED]
