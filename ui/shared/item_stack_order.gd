class_name ItemStackOrder
extends RefCounted
## Pure ordering for lists of item stacks (inventory, crate contents): gear first,
## then food, then everything else; within a group by natural-case display name,
## then id. Keeps a list stable however its backing dictionary was built or rebuilt
## (removing and re-adding a stack moves its key to the end of the dictionary, which
## used to make rows jump).

enum Category { GEAR, FOOD, OTHER }


# =================
# Primary Functions
# =================

## The keys of `items` ({item_id: count}) in display order. Ids whose ItemDef no
## longer exists sort after every resolvable one, by id, so they never hide a real stack.
static func sorted_item_ids(items: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for item_id: Variant in items:
		ids.append(str(item_id))
	ids.sort_custom(_is_id_before)
	return ids


## Which group a def sorts into. Gear wins over food for an item that is both.
static func category_of(def: ItemDef) -> Category:
	if Equipment.is_gear(def):
		return Category.GEAR
	if def.is_food():
		return Category.FOOD
	return Category.OTHER


## Strict ordering of two defs: category, then natural-case display name, then id.
static func is_before(a: ItemDef, b: ItemDef) -> bool:
	# 1. Category: Gear, then food, then the rest.
	var a_category: Category = category_of(a)
	var b_category: Category = category_of(b)
	if a_category != b_category:
		return a_category < b_category
	# 2. Name: Natural-case so "Plank 2" sorts before "Plank 10".
	var name_order: int = a.get_display_name().naturalcasecmp_to(b.get_display_name())
	if name_order != 0:
		return name_order < 0
	# 3. Id: Total order even when two items share a display name.
	return a.id < b.id


# ===================
# Auxiliary Functions
# ===================

static func _is_id_before(a_id: String, b_id: String) -> bool:
	## Auxiliary: is_before over ids, resolving defs via ItemDB and sending unresolved ids last.
	var a: ItemDef = ItemDB.get_def(a_id)
	var b: ItemDef = ItemDB.get_def(b_id)
	if a == null or b == null:
		if a == null and b == null:
			return a_id < b_id
		return a != null
	return is_before(a, b)
