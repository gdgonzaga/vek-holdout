## Subsystem: AI Tasks
## Moves the agent towards a target position, node, job, claim, or group using VoxelPathfinder.
@tool
class_name BTActionNavigateTo
extends BTAction

## Blackboard variable storing the target (Vector3, Vector3i, Node3D, Job, Claim, or Group StringName)
@export var target_var: StringName = &"target_pos"

## Distance to target required to consider arrival successful
@export var arrival_distance: float = 1.8

var _target_world_pos: Vector3 = Vector3.ZERO
var _has_target_pos: bool = false
var _has_valid_target: bool = false


func _generate_name() -> String:
	return "Navigate To  target: %s (dist <= %.1f)" % [
		LimboUtility.decorate_var(target_var),
		arrival_distance
	]


func _enter() -> void:
	_has_valid_target = false
	_has_target_pos = false
	_target_world_pos = Vector3.ZERO
	
	if not agent or not blackboard:
		return
		
	var target: Variant = null
	if blackboard.has_var(target_var):
		target = blackboard.get_var(target_var)
	elif blackboard.has_var(&"target_smart_object"):
		target = blackboard.get_var(&"target_smart_object")
	elif blackboard.has_var(&"active_claim"):
		target = blackboard.get_var(&"active_claim")
	elif blackboard.has_var(&"active_job"):
		target = blackboard.get_var(&"active_job")
	elif blackboard.has_var(&"target_node"):
		target = blackboard.get_var(&"target_node")
	elif blackboard.has_var(&"threat_target"):
		target = blackboard.get_var(&"threat_target")
			
	if target == null:
		return
		
	var path: Array[Vector3] = _resolve_path_to_target(target)
	
	# Check if already within arrival distance
	if _has_target_pos and agent is Node3D:
		var curr_pos: Vector3 = (agent as Node3D).global_position
		if curr_pos.distance_to(_target_world_pos) <= arrival_distance:
			_has_valid_target = true
			return
			
	if path.is_empty():
		return
		
	_has_valid_target = true
	if agent.has_method("set_path"):
		agent.set_path(path)


func _tick(_delta: float) -> Status:
	if not agent or not _has_valid_target:
		return FAILURE
		
	# Check distance to target
	if _has_target_pos and agent is Node3D:
		var curr_pos: Vector3 = (agent as Node3D).global_position
		var dist: float = curr_pos.distance_to(_target_world_pos)
		if dist <= arrival_distance:
			return SUCCESS
			
	if agent.has_method("has_arrived") and bool(agent.has_arrived()):
		return SUCCESS
		
	return RUNNING


func _exit() -> void:
	if agent:
		if agent.has_method("set_path"):
			agent.set_path([])
		if "pathfinder" in agent and agent.pathfinder != null and agent.pathfinder.has_method("clear_diagnostics"):
			agent.pathfinder.clear_diagnostics()


func _resolve_path_to_target(target: Variant) -> Array[Vector3]:
	if not (agent is Node3D):
		return []
		
	var agent_pos: Vector3 = (agent as Node3D).global_position
	
	# Group name string / StringName resolution
	if target is StringName or target is String:
		var group_name := StringName(str(target))
		if agent.get_tree():
			var nodes := agent.get_tree().get_nodes_in_group(group_name)
			var closest: Node3D = null
			var min_d_sq := INF
			for n in nodes:
				if is_instance_valid(n) and not n.is_queued_for_deletion() and n is Node3D:
					var d_sq := agent_pos.distance_squared_to((n as Node3D).global_position)
					if d_sq < min_d_sq:
						min_d_sq = d_sq
						closest = n as Node3D
			if closest != null:
				target = closest
	
	# Extract target position
	if target is Vector3:
		_target_world_pos = target
		_has_target_pos = true
	elif target is Vector3i:
		_target_world_pos = Vector3(target) + Vector3(0.5, 0.5, 0.5)
		_has_target_pos = true
	elif target is Node3D and is_instance_valid(target):
		_target_world_pos = (target as Node3D).global_position
		_has_target_pos = true
	elif target is Object and is_instance_valid(target):
		if "target_pos" in target and target.target_pos is Vector3:
			_target_world_pos = target.target_pos
			_has_target_pos = true
		elif "world_position" in target and target.world_position is Vector3:
			_target_world_pos = target.world_position
			_has_target_pos = true
		elif "target_position" in target and target.target_position is Vector3:
			_target_world_pos = target.target_position
			_has_target_pos = true
		elif "target_node" in target and target.target_node != null and is_instance_valid(target.target_node):
			var node3d: Node3D = target.target_node as Node3D
			if node3d != null:
				_target_world_pos = node3d.global_position
				_has_target_pos = true
		elif "location" in target and target.location is Vector3:
			_target_world_pos = target.location
			_has_target_pos = true
		elif "anchor_cell" in target and target.anchor_cell is Vector3i and target.anchor_cell != Vector3i.MAX:
			_target_world_pos = Vector3(target.anchor_cell) + Vector3(0.5, 0.5, 0.5)
			_has_target_pos = true
			
	if not ("pathfinder" in agent) or agent.pathfinder == null:
		return []
		
	var pathfinder = agent.pathfinder
	if target is Node3D and is_instance_valid(target) and target.has_method("get_footprint_cells"):
		var fp: Array = target.get_footprint_cells()
		if not fp.is_empty():
			return pathfinder.find_path_to_footprint_adjacent(agent_pos, fp)
	elif target is Object and is_instance_valid(target) and "target_node" in target and target.target_node != null:
		var tn = target.target_node
		if is_instance_valid(tn) and tn.has_method("get_footprint_cells"):
			var fp_job: Array = tn.get_footprint_cells()
			if not fp_job.is_empty():
				return pathfinder.find_path_to_footprint_adjacent(agent_pos, fp_job)
				
	if _has_target_pos:
		return pathfinder.find_path_to_adjacent(agent_pos, _target_world_pos)
		
	return []
