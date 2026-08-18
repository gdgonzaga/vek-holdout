class_name BlockPlacementController
extends Node3D
## Building placement controller managing block rotation state and ghost preview rotation.
##
## Manages 3-axis orthogonal rotation (yaw, pitch, roll) for block placement,
## updating the ghost preview visual transform and delegating voxel commits to IBlockGrid.

var _current_rot_index: int = 0
var _current_block_def: BlockDef = null
var _preview_node: Node3D = null


func set_active_block_def(def: BlockDef) -> void:
	_current_block_def = def
	reset_rotation()


func rotate_axis(axis: Vector3, step_sign: int = 1) -> void:
	if _current_block_def == null or not _current_block_def.is_rotatable():
		return
	var new_rot: int = VoxelBlockEncoder.rotate_around_axis(_current_rot_index, axis, (PI / 2.0) * float(step_sign))
	_current_rot_index = _current_block_def.sanitize_rotation(new_rot)
	if _preview_node != null:
		_preview_node.transform.basis = VoxelBlockEncoder.rot_index_to_basis(_current_rot_index)


func reset_rotation() -> void:
	_current_rot_index = 0
	if _preview_node != null:
		_preview_node.transform.basis = Basis.IDENTITY


func commit_placement(grid_pos: Vector3i, grid: IBlockGrid) -> void:
	if _current_block_def == null or grid == null:
		return
	grid.set_block(grid_pos, _current_block_def.type_id, _current_rot_index)


func _unhandled_input(event: InputEvent) -> void:
	if UiGate.is_input_blocked():
		return

	if event.is_action_pressed("rotate_pitch", false, true):
		rotate_axis(Vector3.RIGHT, 1)
		_consume_input()
	elif event.is_action_pressed("rotate_roll", false, true):
		rotate_axis(Vector3.FORWARD, 1)
		_consume_input()
	elif event.is_action_pressed("rotate_yaw", false, true) or event.is_action_pressed("rotate_yaw"):
		rotate_axis(Vector3.UP, 1)
		_consume_input()


func _consume_input() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()
