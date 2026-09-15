## Data Schema: PlantOrderMoodletDef
## Designation order moodlet evaluator for harvestable plants and flora (ARCH §6, GDD §6.10).
## Maps active flora orders (&"chop", &"forage", &"remove", &"harvest") to icon array indices.
class_name PlantOrderMoodletDef
extends MoodletDef

## Mapping of order name (StringName or String) to icon array index.
@export var order_icon_map: Dictionary = {
	&"chop": 0,
	&"forage": 1,
	&"remove": 2,
	&"harvest": 3,
}


# =================
# Primary Functions
# =================

func evaluate_icon_index(entity: Node) -> int:
	if entity == null:
		return -1

	# 1. Harvestable Resolution: Query the harvest capability component from entity or its hierarchy.
	var harvestable: Harvestable = _resolve_harvestable_component(entity)
	if harvestable == null:
		return -1

	# 2. Mark Verification: Moodlet stays hidden if the entity is not currently marked for harvest.
	if not harvestable.is_marked_for_harvest():
		return -1

	# 3. Order String Retrieval: Query the current active designation order type.
	var order_type: String = harvestable.get_order_type()

	# 4. Icon Mapping: Look up the icon index assigned to the resolved order type.
	return _resolve_icon_index_for_order(order_type)


# ===================
# Auxiliary Functions
# ===================

func _resolve_harvestable_component(entity: Node) -> Harvestable:
	## Auxiliary: Resolves Harvestable capability component from node directly, child, or parent.
	if entity is Harvestable:
		return entity as Harvestable
	for child in entity.get_children():
		if child is Harvestable:
			return child as Harvestable
	var parent := entity.get_parent()
	if parent != null:
		if parent is Harvestable:
			return parent as Harvestable
		for sibling in parent.get_children():
			if sibling is Harvestable:
				return sibling as Harvestable
	return null


func _resolve_icon_index_for_order(order_type: String) -> int:
	## Auxiliary: Resolves the integer icon index for an order type name, returning -1 if unmapped.
	var string_name_key := StringName(order_type)
	if order_icon_map.has(string_name_key):
		return int(order_icon_map[string_name_key])
	if order_icon_map.has(order_type):
		return int(order_icon_map[order_type])
	return -1
