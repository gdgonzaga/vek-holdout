## Subsystem: AI Tasks
## Attacks and breaks solid voxels obstructing the enemy path using IBlockGrid.
@tool
class_name BTActionBreachVoxel
extends BTAction

## Blackboard variable storing the obstructing cell coordinate (Vector3i)
@export var target_cell_var: StringName = &"obstructing_voxel_cell"

## Damage dealt to voxel per swing
@export var voxel_damage: int = 25

## Swing duration in seconds
@export var swing_duration: float = 0.8

var _elapsed: float = 0.0


func _generate_name() -> String:
	return "Breach Voxel  cell: %s (dmg: %d)" % [
		LimboUtility.decorate_var(target_cell_var),
		voxel_damage
	]


func _enter() -> void:
	_elapsed = 0.0


func _tick(delta: float) -> Status:
	_elapsed += delta
	if _elapsed < swing_duration:
		return RUNNING
		
	var cell := Vector3i.MAX
	if blackboard and blackboard.has_var(target_cell_var):
		cell = blackboard.get_var(target_cell_var)
		
	if cell == Vector3i.MAX:
		# Fallback: check voxel right in front of agent
		if agent is Node3D:
			var forward: Vector3 = -(agent as Node3D).global_transform.basis.z.normalized()
			cell = Vector3i(((agent as Node3D).global_position + forward).floor())
			
	var grid = agent.get_node_or_null("/root/VoxelGrid") if agent else null
	if grid != null and grid.has_method("damage_voxel"):
		grid.damage_voxel(cell, voxel_damage)
	elif grid != null and grid.has_method("set_voxel"):
		grid.set_voxel(cell, 0)
		
	return SUCCESS
