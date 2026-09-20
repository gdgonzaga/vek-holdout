class_name GearText
extends RefCounted
## Pure naming helpers shared by the Gear sub-tab (slot rows, picker rows, status text).
## Keeps one copy of the slot alias table so the slot list, picker and details panel can
## never disagree on what a slot is called. Item names come from ItemDef.get_display_name().

## Display name overrides for slots whose UI label differs from their slot ID.
## Add entries here when a slot's canonical name needs a player-facing alias.
const SLOT_DISPLAY_NAMES: Dictionary = {
	"holster": "Sidearm",
}

## Prefix carried by armor slot tags (equip_head, equip_torso, ...); dropped for group labels.
const EQUIP_TAG_PREFIX: String = "equip_"

# =================
# Primary Functions
# =================

## Player-facing slot name, applying SLOT_DISPLAY_NAMES aliases over title-cased slot ids.
static func slot_display_name(slot_id: String) -> String:
	return SLOT_DISPLAY_NAMES.get(slot_id, slot_id.replace("_", " ").capitalize())


## Picker group header for an accepted slot tag ("equip_head" -> "Head", "weapon" -> "Weapon").
static func group_label(tag: String) -> String:
	return tag.trim_prefix(EQUIP_TAG_PREFIX).replace("_", " ").capitalize()


## Single-letter stand-in shown in the icon cell of items that have no authored icon.
static func first_glyph(display_name: String) -> String:
	if display_name.is_empty():
		return "?"
	return display_name.substr(0, 1).to_upper()
