class_name StructureTool
extends Node
## Manages tool state, active structure selection, rotation, height offset,
## horizontal nudging, and 3D ghost preview rendering for structure placement
## in the Map Editor (ARCH "Map Editor").

const GhostPreviewBuilderClass = preload("res://subsystems/map_authoring/ghost_preview_builder.gd")

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

## Cached parsed voxel data for the active structure.
var _cached_vox_data: VoxData = null

## 3D preview mesh instance in the editor world.
var _ghost_mesh_instance: MeshInstance3D = null


func _ready() -> void:
	_ensure_ghost_instance()


func _ensure_ghost_instance() -> void:
	if _ghost_mesh_instance == null:
		_ghost_mesh_instance = MeshInstance3D.new()
		_ghost_mesh_instance.name = "StructureGhostMesh"
		_ghost_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost_mesh_instance.visible = false
		add_child(_ghost_mesh_instance)


func activate() -> void:
	is_active = true
	_ensure_ghost_instance()
	if active_structure != null and _cached_vox_data == null:
		_rebuild_ghost_mesh()
	activated.emit()


func deactivate() -> void:
	is_active = false
	hide_ghost()
	deactivated.emit()


func set_active_structure(def: StructureDef) -> void:
	active_structure = def
	_rebuild_ghost_mesh()
	structure_changed.emit(def)


func get_active_structure() -> StructureDef:
	return active_structure


func get_cached_vox_data() -> VoxData:
	if _cached_vox_data == null and active_structure != null and not active_structure.vox_file_path.is_empty():
		_rebuild_ghost_mesh()
	return _cached_vox_data


func set_cached_vox_data(vox_data: VoxData) -> void:
	_cached_vox_data = vox_data
	_update_ghost_mesh_from_data()


func get_ghost_mesh_instance() -> MeshInstance3D:
	_ensure_ghost_instance()
	return _ghost_mesh_instance


func is_ghost_visible() -> bool:
	return _ghost_mesh_instance != null and _ghost_mesh_instance.visible


func show_ghost() -> void:
	if _ghost_mesh_instance != null and is_active and active_structure != null:
		_ghost_mesh_instance.visible = true


func hide_ghost() -> void:
	if _ghost_mesh_instance != null:
		_ghost_mesh_instance.visible = false


func rotate_clockwise() -> void:
	current_rotation = (current_rotation + 1) % 4
	_update_ghost_transform()
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func rotate_counter_clockwise() -> void:
	current_rotation = (current_rotation + 3) % 4
	_update_ghost_transform()
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func set_rotation(rot: int) -> void:
	current_rotation = posmod(rot, 4)
	_update_ghost_transform()
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func adjust_y_offset(delta: int) -> void:
	current_y_offset += delta
	_update_ghost_transform()
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func set_y_offset(offset: int) -> void:
	current_y_offset = offset
	_update_ghost_transform()
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func nudge(offset: Vector3i) -> void:
	current_nudge += offset
	_update_ghost_transform()
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func set_nudge(nudge_vec: Vector3i) -> void:
	current_nudge = nudge_vec
	_update_ghost_transform()
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func reset_transform() -> void:
	current_rotation = 0
	current_y_offset = 0
	current_nudge = Vector3i.ZERO
	_update_ghost_transform()
	transform_changed.emit(current_rotation, current_y_offset, current_nudge)


func calculate_pivot_offset() -> Vector3i:
	if active_structure == null:
		return Vector3i.ZERO
	return StructureStamper.calculate_pivot_offset(active_structure, _cached_vox_data)


func get_placement_origin(base_pos: Vector3i) -> Vector3i:
	return base_pos + Vector3i(current_nudge.x, current_nudge.y + current_y_offset, current_nudge.z)


func update_ghost_position(base_pos: Vector3i) -> void:
	current_grid_position = base_pos
	_update_ghost_transform()


func _update_ghost_transform() -> void:
	_ensure_ghost_instance()
	if not is_active or active_structure == null or _ghost_mesh_instance.mesh == null:
		_ghost_mesh_instance.visible = false
		return

	var origin := get_placement_origin(current_grid_position)
	var pivot := calculate_pivot_offset()
	var rot_basis := Basis(Vector3.UP, deg_to_rad(float(current_rotation * 90)))

	_ghost_mesh_instance.global_transform = Transform3D(
		rot_basis,
		Vector3(origin) - rot_basis * Vector3(pivot)
	)
	_ghost_mesh_instance.visible = true


func _rebuild_ghost_mesh() -> void:
	_ensure_ghost_instance()
	if active_structure == null or active_structure.vox_file_path.is_empty():
		_cached_vox_data = null
		_ghost_mesh_instance.mesh = null
		_ghost_mesh_instance.visible = false
		return

	if ResourceLoader.exists(active_structure.vox_file_path):
		_cached_vox_data = VoxParser.parse_file(active_structure.vox_file_path)
	else:
		_cached_vox_data = null

	_update_ghost_mesh_from_data()


func _update_ghost_mesh_from_data() -> void:
	_ensure_ghost_instance()
	if _cached_vox_data != null:
		var mapping: VoxPaletteMapping = active_structure.palette_mapping if active_structure != null else null
		_ghost_mesh_instance.mesh = GhostPreviewBuilderClass.build_mesh(_cached_vox_data, mapping)
		_update_ghost_transform()
	else:
		_ghost_mesh_instance.mesh = null
		_ghost_mesh_instance.visible = false


## Stamps the active structure into grid at the given base grid position.
## Applies nudge, y_offset, rotation, and pivot offset.
## Returns the array of operation records for undo history.
func stamp(grid: VoxelGridAdapter, base_pos: Vector3i) -> Array[Dictionary]:
	if active_structure == null or grid == null:
		return []

	var vox_data := get_cached_vox_data()
	if vox_data == null:
		push_warning("StructureTool.stamp: no vox data for structure=%s" % active_structure.vox_file_path)
		return []

	var origin := get_placement_origin(base_pos)
	return StructureStamper.stamp_structure(grid, active_structure, vox_data, origin, current_rotation)


## Computes the world-space bounding box (AABB) of the placed structure.
func calculate_bounding_box(base_pos: Vector3i) -> AABB:
	if active_structure == null:
		return AABB(Vector3(base_pos), Vector3.ZERO)

	var vox_data := get_cached_vox_data()
	var origin := get_placement_origin(base_pos)
	return StructureStamper.calculate_bounding_box(active_structure, vox_data, origin, current_rotation)
