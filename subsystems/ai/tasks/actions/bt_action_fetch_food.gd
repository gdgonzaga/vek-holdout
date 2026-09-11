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

	# 2. Source Extraction: Fetch food source variant safely without prematurely casting freed instances.
	var raw_source: Variant = _read_blackboard_source()

	var item_id: String = ""
	if blackboard.has_var(food_item_var):
		item_id = str(blackboard.get_var(food_item_var))

	# 3. Defensive Validation: Reject null, deleted, or invalid instances before type-casting to Node.
	if not is_instance_valid(raw_source) or not (raw_source is Node) or (raw_source as Node).is_queued_for_deletion() or item_id == "":
		# 4. Blackboard Cleanup: Clear dangling references to freed target items to prevent soft-locks.
		_clear_invalid_food_source()
		return FAILURE

	var source_node := raw_source as Node

	# 5. Source Withdrawal: Transfer 1 food unit from source crate or ground item into pockets.
	var transfer_success: bool = _withdraw_food_from_source(source_node, item_id, source_type)
	if transfer_success:
		return SUCCESS

	# 6. Withdrawal Failure Cleanup: Clear stale blackboard entries if item was consumed or vanished.
	_clear_invalid_food_source()
	return FAILURE


# ===================
# Auxiliary Functions
# ===================

func _read_blackboard_source() -> Variant:
	## Auxiliary: Retrieves raw food source variant from blackboard without typed assignment.
	if blackboard != null and blackboard.has_var(food_source_var):
		return blackboard.get_var(food_source_var)
	return null


func _clear_invalid_food_source() -> void:
	## Auxiliary: Cleans up invalid, deleted, or emptied food target references from blackboard.
	if blackboard == null:
		return
	if blackboard.has_var(food_source_var):
		blackboard.erase_var(food_source_var)
	if blackboard.has_var(food_type_var):
		blackboard.erase_var(food_type_var)
	if blackboard.has_var(food_item_var):
		blackboard.erase_var(food_item_var)
	if blackboard.has_var(&"target_smart_object"):
		blackboard.set_var(&"target_smart_object", null)


func _withdraw_food_from_source(source: Node, item_id: String, source_type: StringName) -> bool:
	## Auxiliary: Resolves source container or ground item and moves 1 unit to agent inventory.
	if not is_instance_valid(source) or source.is_queued_for_deletion():
		return false

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
	if not is_instance_valid(ground_item) or ground_item.is_queued_for_deletion():
		return false
	var world_item := ground_item as WorldItem
	if world_item == null:
		return false
	if world_item.item_id != item_id or world_item.count <= 0:
		return false

	world_item.count -= 1
	dest_inv.add(item_id, 1)
	if world_item.count <= 0:
		world_item.queue_free()
	return true
