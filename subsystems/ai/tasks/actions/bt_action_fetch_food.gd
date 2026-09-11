@tool
class_name BTActionFetchFood
extends BTAction
## AI Task: Retrieves 1 unit of food from a target crate or ground WorldItem into pockets.
## If food was already located in inventory, succeeds immediately without transfer.
## Fails gracefully if the food was taken by another colonist, preventing soft-locks.

@export var food_source_var: StringName = &"food_source_node"
@export var food_item_var: StringName = &"food_item_id"
@export var food_type_var: StringName = &"food_source_type"


# =================
# Primary Functions
# =================

func _generate_name() -> String:
	return "Fetch Food  source: %s, item: %s" % [
		LimboUtility.decorate_var(food_source_var),
		LimboUtility.decorate_var(food_item_var)
	]


func _tick(_delta: float) -> Status:
	if not agent or not blackboard:
		return FAILURE

	var source_type: StringName = &""
	if blackboard.has_var(food_type_var):
		source_type = blackboard.get_var(food_type_var)

	# 1. Pocket Bypass: If food is already in carried pockets, no transfer is needed.
	if source_type == &"inventory":
		return SUCCESS

	var source_node: Node = null
	if blackboard.has_var(food_source_var):
		source_node = blackboard.get_var(food_source_var)

	var item_id: String = ""
	if blackboard.has_var(food_item_var):
		item_id = blackboard.get_var(food_item_var)

	if source_node == null or not is_instance_valid(source_node) or item_id == "":
		return FAILURE

	# 2. Source Withdrawal: Transfer 1 food unit from source crate or ground item into pockets.
	var transfer_success: bool = _withdraw_food_from_source(source_node, item_id, source_type)
	if transfer_success:
		return SUCCESS

	return FAILURE


# ===================
# Auxiliary Functions
# ===================

func _withdraw_food_from_source(source: Node, item_id: String, source_type: StringName) -> bool:
	## Auxiliary: Resolves source container or ground item and moves 1 unit to agent inventory.
	var agent_inv: CharacterInventory = null
	if "inventory" in agent and agent.inventory is CharacterInventory:
		agent_inv = agent.inventory
	elif agent.has_node("Inventory"):
		agent_inv = agent.get_node("Inventory") as CharacterInventory

	if agent_inv == null:
		return false

	if source_type == &"crate" or source is Furniture:
		# 1. Crate Withdrawal: Extract 1 item from crate StorageInventory.
		return _withdraw_from_crate(source, item_id, agent_inv)
	elif source_type == &"ground" or source is WorldItem:
		# 2. Ground Item Pickup: Collect 1 item from WorldItem entity.
		return _withdraw_from_ground(source, item_id, agent_inv)

	return false


func _withdraw_from_crate(crate: Node, item_id: String, dest_inv: CharacterInventory) -> bool:
	## Auxiliary: Removes 1 item from crate and deposits into destination inventory.
	var crate_inv: StorageInventory = crate.get_node_or_null("StorageInventory") as StorageInventory
	if crate_inv == null or crate_inv.get_item_count(item_id) <= 0:
		return false

	crate_inv.remove(item_id, 1)
	dest_inv.add(item_id, 1)
	return true


func _withdraw_from_ground(ground_item: Node, item_id: String, dest_inv: CharacterInventory) -> bool:
	## Auxiliary: Consumes or reduces 1 count from ground WorldItem.
	var world_item := ground_item as WorldItem
	if world_item == null or not is_instance_valid(world_item) or world_item.is_queued_for_deletion():
		return false
	if world_item.item_id != item_id or world_item.count <= 0:
		return false

	world_item.count -= 1
	dest_inv.add(item_id, 1)
	if world_item.count <= 0:
		world_item.queue_free()
	return true
