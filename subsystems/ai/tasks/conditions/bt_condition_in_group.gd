## Subsystem: AI Tasks
## Checks if any living node in a specific group is within range, and stores the closest in blackboard.
@tool
class_name BTConditionInGroup
extends BTCondition

## Target node group to scan for
@export var group: StringName = &"enemies"

## Proximity detection radius in meters
@export var radius: float = 12.0

## Blackboard variable where the closest matching node is written
@export var result_var: StringName = &"threat_target"


func _generate_name() -> String:
	return "In Group  %s within %.1fm -> %s" % [
		group,
		radius,
		LimboUtility.decorate_var(result_var)
	]


func _tick(_delta: float) -> Status:
	if not agent or not agent.get_tree():
		return FAILURE
		
	var nodes: Array[Node] = agent.get_tree().get_nodes_in_group(group)
	if nodes.is_empty():
		return FAILURE
		
	var closest_node: Node3D = null
	var closest_dist_sq: float = radius * radius
	var agent_pos: Vector3 = agent.global_position if agent is Node3D else Vector3.ZERO
	
	for node in nodes:
		if node == agent or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var node3d := node as Node3D
		if node3d == null:
			continue
		var dist_sq: float = agent_pos.distance_squared_to(node3d.global_position)
		if dist_sq <= closest_dist_sq:
			closest_dist_sq = dist_sq
			closest_node = node3d
			
	if closest_node != null:
		if blackboard and result_var != &"":
			blackboard.set_var(result_var, closest_node)
		return SUCCESS
		
	return FAILURE
