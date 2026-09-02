class_name CommandController
extends Node3D
## Tactical Command & Deployment placement controller.
##
## Active when command mode is initiated (single colonist or squad).
## Owns crosshair raycasting onto terrain, dynamic path reachability checks,
## formation calculation (cluster vs click-and-drag line), and order dispatching.

const _RAY_DISTANCE := 40.0
const _DRAG_LINE_THRESHOLD := 1.2 # world units to differentiate click from drag

var _active: bool = false
var _target_colonist_ids: Array[String] = []
var _is_dragging: bool = false
var _drag_start_world: Vector3 = Vector3.ZERO
var _current_target_world: Vector3 = Vector3.ZERO
var _has_hit: bool = false

var _marker_pool: Array[Node3D] = []
var _mat_valid: StandardMaterial3D
var _mat_invalid: StandardMaterial3D

var _camera: Camera3D = null
var _last_calculated_positions: Array[Vector3] = []
var _is_reachable: bool = true


func _ready() -> void:
	_init_materials()
	EventBus.command_mode_requested.connect(start_command_mode)


func _init_materials() -> void:
	_mat_valid = StandardMaterial3D.new()
	_mat_valid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_valid.albedo_color = Color(0.2, 0.9, 0.3, 0.75)

	_mat_invalid = StandardMaterial3D.new()
	_mat_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_invalid.albedo_color = Color(0.95, 0.25, 0.2, 0.75)


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func start_command_mode(colonist_ids: Array) -> void:
	_target_colonist_ids.clear()
	for id in colonist_ids:
		_target_colonist_ids.append(str(id))

	if _target_colonist_ids.is_empty():
		cancel_command()
		return

	_active = true
	_is_dragging = false
	_has_hit = false
	_is_reachable = true
	_ensure_marker_pool(_target_colonist_ids.size())
	_update_markers_visibility(false)


func cancel_command() -> void:
	_active = false
	_is_dragging = false
	_target_colonist_ids.clear()
	_last_calculated_positions.clear()
	_update_markers_visibility(false)


func is_active() -> bool:
	return _active


func _process(_delta: float) -> void:
	if not _active or UiGate.is_input_blocked():
		if _active:
			_update_markers_visibility(false)
		return

	var cam := _get_active_camera()
	if cam == null:
		return

	_perform_raycast(cam)
	if not _has_hit:
		_update_markers_visibility(false)
		return

	_calculate_formation_positions()
	_update_markers_display()


func _get_active_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	var viewport := get_viewport()
	if viewport != null:
		return viewport.get_camera_3d()
	return null


func _perform_raycast(cam: Camera3D) -> void:
	var viewport := get_viewport()
	var center := viewport.get_visible_rect().size / 2.0
	var origin := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var space := get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * _RAY_DISTANCE)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 1 | 4

	var parent_body := get_parent() as CollisionObject3D
	if parent_body != null:
		query.exclude = [parent_body.get_rid()]

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_has_hit = false
	else:
		_has_hit = true
		_current_target_world = hit.position


func _calculate_formation_positions() -> void:
	_last_calculated_positions.clear()
	var count := _target_colonist_ids.size()
	if count == 0:
		return

	if count == 1:
		# Single colonist reachability
		var target_pos := _snap_to_ground(_current_target_world)
		_last_calculated_positions.append(target_pos)
		_is_reachable = _check_single_colonist_reachability(_target_colonist_ids[0], target_pos)
	else:
		# Squad
		if _is_dragging and _drag_start_world.distance_to(_current_target_world) >= _DRAG_LINE_THRESHOLD:
			# Drag line formation
			_last_calculated_positions = _calculate_line_formation(_drag_start_world, _current_target_world, count)
		else:
			# Cluster formation around target
			_last_calculated_positions = _calculate_cluster_formation(_current_target_world, count)
		_is_reachable = true


func _check_single_colonist_reachability(colonist_id: String, target_pos: Vector3) -> bool:
	if Colony == null:
		return true
	var colonist := Colony.get_colonist(colonist_id)
	if colonist == null or not is_instance_valid(colonist):
		return true
	if colonist.pathfinder != null and colonist.pathfinder.has_method("find_path_world"):
		var path: PackedVector3Array = colonist.pathfinder.find_path_world(colonist.global_position, target_pos)
		if path.is_empty():
			return false
	return true


func _calculate_cluster_formation(center: Vector3, count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var center_snapped := _snap_to_ground(center)
	positions.append(center_snapped)

	if count == 1:
		return positions

	# Spiral out in 2D grid offsets to find nearest walkable cells
	var offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)
	]

	var idx := 0
	while positions.size() < count and idx < offsets.size():
		var off := offsets[idx]
		var candidate := center + Vector3(off.x, 0, off.y)
		positions.append(_snap_to_ground(candidate))
		idx += 1

	while positions.size() < count:
		positions.append(center_snapped)

	return positions


func _calculate_line_formation(start_pt: Vector3, end_pt: Vector3, count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for i in range(count):
		var t := float(i) / float(maxi(1, count - 1))
		var pt := start_pt.lerp(end_pt, t)
		positions.append(_snap_to_ground(pt))
	return positions


func _snap_to_ground(pos: Vector3) -> Vector3:
	if Colony != null and Colony.has_method("get_ground_height_at"):
		var gy: float = Colony.get_ground_height_at(pos.x, pos.z)
		if not is_nan(gy):
			return Vector3(pos.x, gy, pos.z)
	return Vector3(pos.x, roundf(pos.y), pos.z)


func _ensure_marker_pool(size: int) -> void:
	while _marker_pool.size() < size:
		var marker := _create_marker_node()
		add_child(marker)
		_marker_pool.append(marker)


func _create_marker_node() -> Node3D:
	var root := Node3D.new()

	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.4
	cyl.height = 0.05
	mesh_inst.mesh = cyl
	mesh_inst.position = Vector3(0, 0.025, 0)
	root.add_child(mesh_inst)

	var beam := MeshInstance3D.new()
	var beam_cyl := CylinderMesh.new()
	beam_cyl.top_radius = 0.04
	beam_cyl.bottom_radius = 0.04
	beam_cyl.height = 1.0
	beam.mesh = beam_cyl
	beam.position = Vector3(0, 0.5, 0)
	root.add_child(beam)

	return root


func _update_markers_visibility(vis: bool) -> void:
	for m in _marker_pool:
		m.visible = vis


func _update_markers_display() -> void:
	var mat := _mat_valid if _is_reachable else _mat_invalid
	var count := _last_calculated_positions.size()

	for i in range(_marker_pool.size()):
		var marker := _marker_pool[i]
		if i < count:
			marker.visible = true
			marker.global_position = _last_calculated_positions[i]
			for child in marker.get_children():
				if child is MeshInstance3D:
					child.material_override = mat
		else:
			marker.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _active or UiGate.is_input_blocked():
		return

	if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		cancel_command()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _has_hit:
				print("has hit")
				if _target_colonist_ids.size() > 1:
					_is_dragging = true
					_drag_start_world = _current_target_world
				else:
					print("commit command")
					_commit_command()
				get_viewport().set_input_as_handled()
		else:
			if _is_dragging:
				_is_dragging = false
				_commit_command()
				get_viewport().set_input_as_handled()


func _commit_command() -> void:
	if _last_calculated_positions.is_empty() or _target_colonist_ids.is_empty():
		cancel_command()
		return

	var orders: Dictionary = {}
	for i in range(_target_colonist_ids.size()):
		var cid: String = _target_colonist_ids[i]
		var pos: Vector3 = _last_calculated_positions[mini(i, _last_calculated_positions.size() - 1)]
		orders[cid] = pos
		if Colony != null:
			Colony.deploy_colonist(cid, pos)

	EventBus.deploy_orders_issued.emit(orders)
	cancel_command()
