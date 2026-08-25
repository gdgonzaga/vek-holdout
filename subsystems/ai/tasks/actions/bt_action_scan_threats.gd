## Subsystem: AI Tasks
## Scans for valid threats (Player > Core > Colonists) within sensory radius.
@tool
class_name BTActionScanThreats
extends BTAction

## Sensory detection radius in meters
@export var radius: float = 16.0

## Blackboard variable where the selected threat node is stored
@export var result_var: StringName = &"threat_target"

## Groups to scan in priority order
@export var threat_groups: Array[StringName] = [&"players", &"core", &"colonists"]


func _generate_name() -> String:
	return "Scan Threats  radius: %.1fm -> %s" % [
		radius,
		LimboUtility.decorate_var(result_var)
	]


func _tick(_delta: float) -> Status:
	if not agent or not agent.get_tree():
		return FAILURE
		
	var agent_pos: Vector3 = (agent as Node3D).global_position if agent is Node3D else Vector3.ZERO
	var max_dist_sq: float = radius * radius
	
	for group_name in threat_groups:
		var nodes: Array[Node] = agent.get_tree().get_nodes_in_group(group_name)
		var closest_node: Node3D = null
		var closest_dist_sq: float = max_dist_sq
		
		for node in nodes:
			if node == agent or not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			var node3d := node as Node3D
			if node3d == null:
				continue
			# Exclude dead entities if supported
			if "is_dead" in node3d and bool(node3d.is_dead):
				continue
			if "_is_dead" in node3d and bool(node3d._is_dead):
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
