## Subsystem: AI Tasks
## Evaluates if direct navigation path toward target is obstructed by solid terrain/voxels.
@tool
class_name BTConditionPathBlocked
extends BTCondition

## Blackboard variable storing the target
@export var target_var: StringName = &"threat_target"

## Blackboard variable where the detected obstructing cell is stored
@export var result_cell_var: StringName = &"obstructing_voxel_cell"


func _generate_name() -> String:
	return "Path Blocked  target: %s -> %s" % [
		LimboUtility.decorate_var(target_var),
		LimboUtility.decorate_var(result_cell_var)
	]


func _tick(_delta: float) -> Status:
	if not agent or not blackboard:
		return FAILURE
		
	var target: Node3D = null
	if blackboard.has_var(target_var):
		target = blackboard.get_var(target_var) as Node3D
		
	if not is_instance_valid(target):
		return FAILURE
		
	if not (agent is Node3D):
		return FAILURE
		
	# Raycast / step forward check for solid obstacles
	var agent_pos: Vector3 = (agent as Node3D).global_position
	var dir: Vector3 = (target.global_position - agent_pos).normalized()
	var forward_cell := Vector3i((agent_pos + dir * 1.0 + Vector3(0, 0.5, 0)).floor())
	
	var grid = agent.get_node_or_null("/root/VoxelGrid")
	if grid != null and grid.has_method("get_voxel"):
		var val: int = int(grid.get_voxel(forward_cell))
		if val > 0:
			blackboard.set_var(result_cell_var, forward_cell)
			return SUCCESS
			
	return FAILURE
