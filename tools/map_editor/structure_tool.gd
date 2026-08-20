class_name StructureTool
extends Node
## Manages tool state, active structure selection, rotation, height offset,
## and horizontal nudging for structure placement in the Map Editor.

signal activated()
signal deactivated()
signal structure_changed(def: StructureDef)
signal transform_changed(rotation: int, y_offset: int, nudge: Vector3i)

## The currently selected StructureDef resource.
var active_structure: StructureDef = null

## Whether the tool is currently active in the Map Editor.
var is_active: bool = false

## Y-axis rotation in quarter turns (0 = 0 deg, 1 = 90 deg, 2 = 180 deg, 3 = 270 deg).
var current_rotation: int = 0

## Height offset applied along the Y-axis (voxel units).
var current_y_offset: int = 0

## Horizontal nudge offset applied on the X/Z plane (voxel units).
var current_nudge: Vector3i = Vector3i.ZERO

## Last hovered base grid position.
var current_grid_position: Vector3i = Vector3i.ZERO


func activate() -> void:
	is_active = true
	activated.emit()


func deactivate() -> void:
	is_active = false
	deactivated.emit()


func set_active_structure(def: StructureDef) -> void:
	active_structure = def
	structure_changed.emit(def)


func get_active_structure() -> StructureDef:
	return active_structure


func rotate_clockwise() -> void:
	current_rotation = (current_rotation + 1) % 4
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func rotate_counter_clockwise() -> void:
	current_rotation = (current_rotation + 3) % 4
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func set_rotation(rot: int) -> void:
	current_rotation = posmod(rot, 4)
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func adjust_y_offset(delta: int) -> void:
	current_y_offset += delta
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func set_y_offset(offset: int) -> void:
	current_y_offset = offset
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func nudge(offset: Vector3i) -> void:
	current_nudge += offset
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func set_nudge(nudge_vec: Vector3i) -> void:
	current_nudge = nudge_vec
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func reset_transform() -> void:
	current_rotation = 0
	current_y_offset = 0
	current_nudge = Vector3i.ZERO
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func calculate_pivot_offset() -> Vector3i:
	if active_structure == null:
		return Vector3i.ZERO
	return StructureStamper.calculate_pivot_offset(active_structure)


func get_placement_origin(base_pos: Vector3i) -> Vector3i:
	return base_pos + Vector3i(current_nudge.x, current_nudge.y + current_y_offset, current_nudge.z)
