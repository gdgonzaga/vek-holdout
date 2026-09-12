@tool
class_name BTActionFindFood
extends BTAction
## AI Task: Locates the best available food source for a colonist.
## Prioritizes carried inventory pockets (zero travel time), followed by
## the nearest accessible storage crate or unforbidden world item.

@export var goal_var: StringName = &"current_goal"
@export var expected_goal: StringName = &"eat"
@export var food_source_var: StringName = &"food_source_node"
@export var food_item_var: StringName = &"food_item_id"
@export var food_type_var: StringName = &"food_source_type"
@export var target_pos_var: StringName = &"target_pos"
@export var target_smart_object_var: StringName = &"target_smart_object"


# =================
# Primary Functions
# =================

func _generate_name() -> String:
	return "Find Food  source: %s, item: %s" % [
		LimboUtility.decorate_var(food_source_var),
		LimboUtility.decorate_var(food_item_var)
	]


func _tick(_delta: float) -> Status:
	if not agent or not blackboard:
		return FAILURE

	# 1. Goal Validation: Only execute if active goal matches the expected goal (default &"eat").
	if expected_goal != &"" and blackboard.has_var(goal_var):
		var active_goal = blackboard.get_var(goal_var)
		if active_goal != expected_goal:
			return FAILURE

	# 2. Pocket Evaluation: Prioritize consuming food already in carried inventory.
	var pocket_item: String = _find_edible_in_inventory()
	if pocket_item != "":
		blackboard.set_var(food_type_var, &"inventory")
		blackboard.set_var(food_source_var, agent)
		blackboard.set_var(food_item_var, pocket_item)
		if target_smart_object_var != &"":
			blackboard.set_var(target_smart_object_var, agent)
		if agent is Node3D:
			blackboard.set_var(target_pos_var, (agent as Node3D).global_position)
		return SUCCESS

	# 2. Colony Storage Search: Locate nearest non-blacklisted food source in colony.
	var food_data: Dictionary = _find_colony_food_source()
	if not food_data.is_empty():
		var source_node: Node = food_data.get("source_node")
		var item_id: String = food_data.get("item_id", "")
		var source_type: String = food_data.get("source_type", "crate")

		blackboard.set_var(food_type_var, StringName(source_type))
		blackboard.set_var(food_source_var, source_node)
		blackboard.set_var(food_item_var, item_id)
		if target_smart_object_var != &"":
			blackboard.set_var(target_smart_object_var, source_node)
		if source_node is Node3D:
			blackboard.set_var(target_pos_var, (source_node as Node3D).global_position)
		return SUCCESS

	return FAILURE


# ===================
# Auxiliary Functions
# ===================

func _find_edible_in_inventory() -> String:
	## Auxiliary: Searches agent carry pockets for any item matching FoodParams or the food tag.
	var inv: CharacterInventory = AIUtils.resolve_character_inventory(agent)
	if inv == null or inv.items == null or not (inv.items is Dictionary):
		return ""

	for item_key in inv.items.keys():
		var iid := str(item_key)
		if inv.get_item_count(iid) > 0 and _is_edible(iid):
			return iid
	return ""


func _find_colony_food_source() -> Dictionary:
	## Auxiliary: Queries StorageRegistry for the nearest unblacklisted food source.
	if not (agent is Node3D):
		return {}

	var colony: Node = agent.get_node_or_null("/root/Colony")
	if colony == null or not ("storage_registry" in colony) or colony.storage_registry == null:
		return {}

	var registry: StorageRegistry = colony.storage_registry
	var blacklisted: Array = []
	var brain: ColonistBrain = agent.get_node_or_null("ColonistBrain") as ColonistBrain
	if brain != null:
		blacklisted = brain.get_blacklisted_food_sources()

	var agent_pos: Vector3 = (agent as Node3D).global_position
	return registry.find_best_food_source(agent_pos, blacklisted)


func _is_edible(item_id: String) -> bool:
	## Auxiliary: Checks if item definition carries FoodParams or "food" tag.
	return AIUtils.is_edible_item(item_id)
