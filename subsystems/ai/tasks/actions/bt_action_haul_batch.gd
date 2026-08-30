## Subsystem: AI Tasks
## Executes a batch transfer step for hauling: loading items from source or depositing to target.
@tool
class_name BTActionHaulBatch
extends BTAction

enum Mode { LOAD, UNLOAD }

## Whether this action loads items into inventory or unloads them to the destination
@export var mode: Mode = Mode.LOAD

## Blackboard variable storing the job or claim
@export var job_var: StringName = &"active_job"

## Blackboard variable storing the haul batch amount
@export var batch_amount_var: StringName = &"haul_batch_amount"

## Blackboard variable storing the item ID
@export var item_id_var: StringName = &"haul_item_id"

## Blackboard variable storing the source crate / container node
@export var source_var: StringName = &"source_node"

## Blackboard variable storing the destination sink / container node
@export var target_var: StringName = &"target_node"


func _generate_name() -> String:
	var mode_str := "Load" if mode == Mode.LOAD else "Unload"
	return "Haul Batch (%s)  job: %s" % [
		mode_str,
		LimboUtility.decorate_var(job_var)
	]


func _tick(_delta: float) -> Status:
	if not agent:
		return FAILURE
		
	var inv: CharacterInventory = null
	if "inventory" in agent and agent.inventory is CharacterInventory:
		inv = agent.inventory
		
	if inv == null:
		return FAILURE
		
	var job: Variant = null
	if blackboard:
		if blackboard.has_var(job_var):
			job = blackboard.get_var(job_var)
		elif blackboard.has_var(&"active_claim"):
			job = blackboard.get_var(&"active_claim")
			
	if mode == Mode.LOAD:
		return _execute_load(inv, job)
	else:
		return _execute_unload(inv, job)


func _execute_load(colonist_inv: CharacterInventory, job: Variant) -> Status:
	var source_node: Node = null
	if blackboard and blackboard.has_var(source_var):
		source_node = blackboard.get_var(source_var) as Node
		
	var target_sink: Node = null
	if blackboard and blackboard.has_var(target_var):
		target_sink = blackboard.get_var(target_var) as Node
	elif job != null and "target_node" in job and job.target_node != null:
		target_sink = job.target_node as Node
		
	var needed_ids: Array = []
	if target_sink != null and target_sink.has_method("needed_item_ids"):
		needed_ids = target_sink.needed_item_ids()
	if needed_ids.is_empty() and blackboard and blackboard.has_var(item_id_var):
		var id_str = str(blackboard.get_var(item_id_var))
		if id_str != "":
			needed_ids.append(id_str)
	if needed_ids.is_empty() and job != null and "item_id" in job and str(job.item_id) != "":
		needed_ids.append(str(job.item_id))
		
	var colony: Node = agent.get_node_or_null("/root/Colony")
	if source_node == null and colony != null and "storage_registry" in colony and colony.storage_registry != null:
		var agent_pos: Vector3 = (agent as Node3D).global_position if agent is Node3D else Vector3.ZERO
		source_node = colony.storage_registry.find_source(needed_ids, agent_pos)
		if source_node != null and blackboard:
			blackboard.set_var(source_var, source_node)
			
	if source_node == null:
		return FAILURE
		
	var crate_inv: Inventory = null
	if colony != null and "storage_registry" in colony and colony.storage_registry != null and source_node is Furniture:
		crate_inv = colony.storage_registry.inventory_of(source_node as Furniture)
	if crate_inv == null and "inventory" in source_node and source_node.inventory is Inventory:
		crate_inv = source_node.inventory
	if crate_inv == null and source_node.has_node("StorageInventory"):
		crate_inv = source_node.get_node("StorageInventory") as Inventory
		
	if crate_inv == null:
		return FAILURE
		
	# If needed_ids is still empty, load whatever item is in source crate
	if needed_ids.is_empty():
		for k in crate_inv.items.keys():
			if crate_inv.get_item_count(str(k)) > 0:
				needed_ids.append(str(k))
				
	var transferred_any := false
	for item_id in needed_ids:
		var id_str := str(item_id)
		var need_count: int = 10
		if target_sink != null and target_sink.has_method("remaining_need"):
			need_count = target_sink.remaining_need(id_str)
		elif blackboard and blackboard.has_var(batch_amount_var):
			var b = int(blackboard.get_var(batch_amount_var))
			if b > 0:
				need_count = b
		if need_count <= 0:
			continue
		var before_count: int = colonist_inv.get_item_count(id_str)
		crate_inv.transfer_to(colonist_inv, id_str, need_count)
		if colonist_inv.get_item_count(id_str) > before_count:
			transferred_any = true
			
	return SUCCESS if transferred_any else FAILURE


func _execute_unload(colonist_inv: CharacterInventory, job: Variant) -> Status:
	var target_sink: Node = null
	if blackboard and blackboard.has_var(target_var):
		target_sink = blackboard.get_var(target_var) as Node
	elif job != null and "target_node" in job and job.target_node != null:
		target_sink = job.target_node as Node
		
	var deposited := false
	if target_sink != null and is_instance_valid(target_sink) and not target_sink.is_queued_for_deletion():
		if target_sink.has_method("deposit_from"):
			target_sink.deposit_from(agent)
			deposited = true
		else:
			var target_inv: Inventory = null
			var colony: Node = agent.get_node_or_null("/root/Colony")
			if colony != null and "storage_registry" in colony and colony.storage_registry != null and target_sink is Furniture:
				target_inv = colony.storage_registry.inventory_of(target_sink as Furniture)
			if target_inv == null and "inventory" in target_sink and target_sink.inventory is Inventory:
				target_inv = target_sink.inventory
			if target_inv == null and target_sink.has_node("StorageInventory"):
				target_inv = target_sink.get_node("StorageInventory") as Inventory
				
			if target_inv != null:
				for item_id in colonist_inv.items.keys():
					var count: int = colonist_inv.get_item_count(item_id)
					if count > 0:
						colonist_inv.transfer_to(target_inv, item_id, count)
				deposited = true

	# Unload any remaining surplus to nearest crate
	var colony: Node = agent.get_node_or_null("/root/Colony")
	if colony != null and "storage_registry" in colony and colony.storage_registry != null:
		var agent_pos: Vector3 = (agent as Node3D).global_position if agent is Node3D else Vector3.ZERO
		var crate = colony.storage_registry.nearest_crate(agent_pos)
		if crate != null:
			var crate_inv = colony.storage_registry.inventory_of(crate)
			if crate_inv != null:
				for item_id in colonist_inv.items.keys():
					var count: int = colonist_inv.get_item_count(item_id)
					if count > 0:
						colonist_inv.transfer_to(crate_inv, item_id, count)
				return SUCCESS

	if deposited:
		return SUCCESS

	# If nowhere to unload and still holding items, drop to floor as failsafe
	if agent is Node3D and agent.get_tree() != null and not colonist_inv.items.is_empty():
		var pos: Vector3 = (agent as Node3D).global_position
		for item_id in colonist_inv.items.keys():
			var count: int = colonist_inv.get_item_count(item_id)
			if count > 0:
				colonist_inv.remove(str(item_id), count)
				WorldItem.spawn_at(agent, str(item_id), count, pos + Vector3(0, 0.5, 0))
		return SUCCESS

	return SUCCESS if colonist_inv.items.is_empty() else FAILURE
