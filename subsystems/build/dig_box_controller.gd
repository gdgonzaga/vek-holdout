class_name DigBoxController
extends Node3D
## Controller for Dig Box Designation mode (ARCH "Mining / Designation").
##
## Active when Player.mode == DIG_BOX_DESIGNATION. Casts a screen-center raycast
## onto natural smooth terrain or blocky terrain, calculates orthogonal 6-way
## relative orientation derived from camera look direction (Depth forward into
## view, Height screen-up, Width screen-right), and displays a GhostPreview
## bounding box snapped to the struck voxel cell.

const _RAY_DISTANCE := 30.0

# Runtime-wired dependencies
var grid_adapter: VoxelGridAdapter
var exclude_bodies: Array[PhysicsBody3D] = []

@export var camera_path: NodePath = ^""

var width: int = 1
var height: int = 3
var depth: int = 3

var _ghost: GhostPreview
var _camera: Camera3D
var _active: bool = false


func _ready() -> void:
	_ghost = $GhostPreview
	if camera_path != ^"" and has_node(camera_path):
		_camera = get_node(camera_path)
	EventBus.dig_box_toggled.connect(_on_dig_box_toggled)
	_update_activation()


## Enable or disable the controller.
func set_active(active: bool) -> void:
	_active = active
	_update_activation()


## Runtime camera wiring from the Player.
func set_camera(camera: Camera3D) -> void:
	_camera = camera


## Add a physics body (e.g. the player capsule) to the raycast exclusion list.
func add_exclude_body(body: PhysicsBody3D) -> void:
	if body != null and not exclude_bodies.has(body):
		exclude_bodies.append(body)


func _exclude_rids() -> Array:
	var rids: Array = []
	for body in exclude_bodies:
		if is_instance_valid(body):
			rids.append(body.get_rid())
	return rids


func _update_activation() -> void:
	if not is_node_ready():
		return
	if not _active and _ghost != null:
		_ghost.hide_()


func _on_dig_box_toggled(active: bool) -> void:
	set_active(active)


func _physics_process(_delta: float) -> void:
	if not _active:
		if _ghost != null and _ghost.visible:
			_ghost.hide_()
		return
	
	# Fallback camera resolution if not explicitly wired yet
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	
	# Fallback grid_adapter resolution if not explicitly wired yet
	if grid_adapter == null:
		var parent_node := get_parent()
		if parent_node != null and parent_node.has_method("get_blocky_grid"):
			grid_adapter = VoxelGridAdapter.new()
			grid_adapter.set_grid(parent_node.call("get_blocky_grid"))
			if parent_node.has_method("get_smooth_grid"):
				grid_adapter.set_smooth_grid(parent_node.call("get_smooth_grid"))
	
	if _camera == null or grid_adapter == null:
		return
	
	# Fallback player body exclusion
	if exclude_bodies.is_empty():
		var player_body := get_tree().get_first_node_in_group("player") as PhysicsBody3D
		if player_body == null and get_parent() != null:
			player_body = get_parent().find_child("Player", true, false) as PhysicsBody3D
		if player_body != null:
			add_exclude_body(player_body)
	
	var center := get_viewport().get_visible_rect().size / 2.0
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	var hit := grid_adapter.raycast_to_voxel(origin, dir, _RAY_DISTANCE, _exclude_rids())
	
	if not hit.get("hit", false):
		_ghost.hide_()
		return
	
	_update_preview_ghost(hit)


func _update_preview_ghost(hit: Dictionary) -> void:
	var surface: String = hit.get("surface", "")
	var cell: Vector3i
	
	if surface == "smooth":
		var pt: Vector3 = hit.get("smooth_point", Vector3.ZERO)
		var n: Vector3 = hit.get("smooth_normal", Vector3.UP)
		var hit_in: Vector3 = pt - n * 0.01
		cell = Vector3i(int(floor(hit_in.x)), int(floor(hit_in.y)), int(floor(hit_in.z)))
	else:
		cell = hit.get("position", Vector3i.ZERO)
	
	# Derive 6-way orientation from the player's camera look direction.
	var cam_fwd: Vector3 = -_camera.global_transform.basis.z.normalized()
	var cam_up: Vector3 = _camera.global_transform.basis.y.normalized()
	var dominant_look: Vector3i = get_dominant_cardinal(cam_fwd)
	
	var depth_dir: Vector3
	var height_dir: Vector3
	var width_dir: Vector3
	
	if dominant_look == Vector3i.UP or dominant_look == Vector3i.DOWN:
		# Vertical digging (shafts or ceilings)
		depth_dir = Vector3(dominant_look)
		var horiz_fwd := Vector3(cam_fwd.x, 0.0, cam_fwd.z)
		if horiz_fwd.length_squared() < 0.001:
			horiz_fwd = -Vector3(cam_up.x, 0.0, cam_up.z)
			if horiz_fwd.length_squared() < 0.001:
				horiz_fwd = Vector3.FORWARD
		var height_cardinal := get_dominant_cardinal(horiz_fwd.normalized())
		height_dir = Vector3(height_cardinal)
		width_dir = depth_dir.cross(height_dir)
	else:
		# Horizontal digging (tunnels, rooms, hillside slices)
		depth_dir = Vector3(dominant_look)
		height_dir = Vector3.UP
		width_dir = depth_dir.cross(height_dir)
	
	# Calculate Box Size along world axes.
	var box_size := Vector3(
		absf(float(width) * width_dir.x + float(height) * height_dir.x + float(depth) * depth_dir.x),
		absf(float(width) * width_dir.y + float(height) * height_dir.y + float(depth) * depth_dir.y),
		absf(float(width) * width_dir.z + float(height) * height_dir.z + float(depth) * depth_dir.z)
	)
	
	# Calculate Box Center (anchors: Depth extends forward along look dir, Height upward from cell, Width centered).
	var base_center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var box_center: Vector3 = base_center + depth_dir * ((float(depth) - 1.0) * 0.5) + height_dir * ((float(height) - 1.0) * 0.5)
	
	_ghost.show_box_at(box_center, box_size, true)


## Snap a vector to the closest of the 6 cardinal directions (+/- X, +/- Y, +/- Z).
static func get_dominant_cardinal(v: Vector3) -> Vector3i:
	var abs_x := absf(v.x)
	var abs_y := absf(v.y)
	var abs_z := absf(v.z)
	if abs_y >= abs_x and abs_y >= abs_z:
		return Vector3i.UP if v.y > 0.0 else Vector3i.DOWN
	elif abs_x >= abs_z:
		return Vector3i.RIGHT if v.x > 0.0 else Vector3i.LEFT
	else:
		return Vector3i.BACK if v.z > 0.0 else Vector3i.FORWARD
