## Data Schema: ActivityMoodletDef
## Activity-driven moodlet evaluator for colonist actions and goals (ARCH §6).
## Maps colonist activity identifiers (e.g. &"idle", &"mining", &"eat") to icon array indices.
extends MoodletDef
class_name ActivityMoodletDef

## Mapping of activity name (StringName or String) to icon array index.
@export var activity_icon_map: Dictionary = {}


# =================
# Primary Functions
# =================

func evaluate_icon_index(entity: Node) -> int:
	if entity == null:
		return -1
	
	# 1. Activity Resolution: Query active activity identifier from the entity.
	var activity: StringName = _query_entity_activity(entity)
	if activity == &"":
		return -1
	
	# 2. Icon Mapping: Look up the icon index assigned to the resolved activity.
	return _resolve_icon_index_for_activity(activity)


# ===================
# Auxiliary Functions
# ===================

func _query_entity_activity(entity: Node) -> StringName:
	## Auxiliary: Safely calls get_current_activity on entity.
	if entity.has_method("get_current_activity"):
		return entity.get_current_activity()
	return &""


func _resolve_icon_index_for_activity(activity: StringName) -> int:
	## Auxiliary: Resolves the integer icon index for an activity name, returning -1 if unmapped.
	if activity_icon_map.has(activity):
		return int(activity_icon_map[activity])
	var str_key: String = String(activity)
	if activity_icon_map.has(str_key):
		return int(activity_icon_map[str_key])
	return -1
