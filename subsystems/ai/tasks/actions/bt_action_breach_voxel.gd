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
			
	# 1. Grid Resolution: Locates the current map's BlockyGrid via SceneManager,
	# the same accessor player.gd uses for direct terrain mining.
	var grid: BlockyGrid = _resolve_blocky_grid()
	if grid != null:
		grid.apply_damage(cell, voxel_damage)

	return SUCCESS


func _resolve_blocky_grid() -> BlockyGrid:
	## Auxiliary: Resolves the current map's BlockyGrid, or null if none is loaded.
	if SceneManager == null:
		return null
	var current_map: Node = SceneManager.get_current_map()
	if current_map != null and current_map.has_method("get_blocky_grid"):
		return current_map.get_blocky_grid()
	return null
