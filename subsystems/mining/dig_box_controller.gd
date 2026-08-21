class_name DigBoxController
extends Node3D
## Controller for Dig Box Designation mode (ARCH "Mining / Designation").
##
## Active when Player.mode == DIG_BOX_DESIGNATION. Casts a screen-center raycast
## onto natural smooth terrain or blocky terrain.
##
## Orientation:
##   - Default: Horizontal (Depth along ground plane N/S/E/W, Height +Y)
##   - RMB Toggle: Vertical (Depth down -Y or up +Y, Height along ground plane)
##
## Resizing controls:
##   - Scroll Wheel (no modifiers): Width +/- 1 (clamped 1..11, alternating R/L)
##   - Shift + Scroll (or Wheel Left/Right): Depth +/- 1 (clamped 1..11)
##   - Ctrl + Scroll: Height +/- 1 (clamped 1..11)
##
## Designation:
##   - LMB: Filters all coordinates that actually contain terrain blocks, logs
##     the coordinates, and places persistent visual amber markers on each solid terrain block.

const _RAY_DISTANCE := 30.0

# Runtime-wired dependencies
var grid_adapter: VoxelGridAdapter
var exclude_bodies: Array[PhysicsBody3D] = []

@export var camera_path: NodePath = ^""

var width: int = 1
var height: int = 3
var depth: int = 3
var is_vertical: bool = false

## Minimum fraction of a voxel cell's height (0.0 to 1.0) that must be solid ground to be marked.
## 0.5 means the terrain surface must reach at least the middle of the cell (Y + 0.5).
@export_range(0.0, 1.0, 0.05) var terrain_solidity_threshold: float = 0.5

var _ghost: GhostPreview
var _camera: Camera3D
var _active: bool = false

# Last calculated frame state
var _has_valid_target: bool = false
var _last_cell: Vector3i = Vector3i.ZERO
var _last_depth_dir: Vector3 = Vector3.ZERO
var _last_height_dir: Vector3 = Vector3.ZERO
var _last_width_dir: Vector3 = Vector3.ZERO
var _last_box_center: Vector3 = Vector3.ZERO
var _last_box_size: Vector3 = Vector3.ZERO


func _ready() -> void:
	_ghost = $GhostPreview
	if camera_path != ^"" and has_node(camera_path):
		_camera = get_node(camera_path)
	EventBus.dig_box_toggled.connect(_on_dig_box_toggled)
	EventBus.dig_job_completed.connect(_on_dig_job_completed)
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
	if not _active:
		if _ghost != null:
			_ghost.hide_()
		_has_valid_target = false


func _on_dig_box_toggled(active: bool) -> void:
	set_active(active)
	if active:
		width = 1
		height = 3
		depth = 3
		is_vertical = false
		EventBus.dig_box_dimensions_changed.emit(width, height, depth)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if UiGate.is_input_blocked():
		return
	
	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		var btn: int = mouse_event.button_index
		
		# Left-click confirms dig designation
		if btn == MOUSE_BUTTON_LEFT:
			_try_commit_designation()
			get_viewport().set_input_as_handled()
			return
		
		# Right-click toggles between Horizontal and Vertical orientation
		if btn == MOUSE_BUTTON_RIGHT:
			is_vertical = not is_vertical
			get_viewport().set_input_as_handled()
			return
		
		var is_wheel: bool = btn in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
		if not is_wheel:
			return
		
		var changed := false
		if btn == MOUSE_BUTTON_WHEEL_UP:
			if event.shift_pressed:
				var new_d := clampi(depth + 1, 1, 11)
				if new_d != depth:
					depth = new_d
					changed = true
			elif event.ctrl_pressed:
				var new_h := clampi(height + 1, 1, 11)
				if new_h != height:
					height = new_h
					changed = true
			else:
				var new_w := clampi(width + 1, 1, 11)
				if new_w != width:
					width = new_w
					changed = true
		elif btn == MOUSE_BUTTON_WHEEL_DOWN:
			if event.shift_pressed:
				var new_d := clampi(depth - 1, 1, 11)
				if new_d != depth:
					depth = new_d
					changed = true
			elif event.ctrl_pressed:
				var new_h := clampi(height - 1, 1, 11)
				if new_h != height:
					height = new_h
					changed = true
			else:
				var new_w := clampi(width - 1, 1, 11)
				if new_w != width:
					width = new_w
					changed = true
		elif btn == MOUSE_BUTTON_WHEEL_RIGHT:
			var new_d := clampi(depth + 1, 1, 11)
			if new_d != depth:
				depth = new_d
				changed = true
		elif btn == MOUSE_BUTTON_WHEEL_LEFT:
			var new_d := clampi(depth - 1, 1, 11)
			if new_d != depth:
				depth = new_d
				changed = true
		
		if changed:
			EventBus.dig_box_dimensions_changed.emit(width, height, depth)
			get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if not _active:
		if _ghost != null and _ghost.visible:
			_ghost.hide_()
		_has_valid_target = false
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
		_has_valid_target = false
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
		_has_valid_target = false
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
	
	# Resolve horizontal facing on ground plane (XZ)
	var cam_fwd: Vector3 = -_camera.global_transform.basis.z.normalized()
	var cam_up: Vector3 = _camera.global_transform.basis.y.normalized()
	var horiz_fwd := Vector3(cam_fwd.x, 0.0, cam_fwd.z)
	if horiz_fwd.length_squared() < 0.001:
		horiz_fwd = -Vector3(cam_up.x, 0.0, cam_up.z)
		if horiz_fwd.length_squared() < 0.001:
			horiz_fwd = Vector3.FORWARD
	var dominant_horiz_look: Vector3i = get_dominant_cardinal(horiz_fwd.normalized())
	
	var depth_dir: Vector3
	var height_dir: Vector3
	var width_dir: Vector3
	
	if is_vertical:
		# Vertical mode: Depth extends vertically (-Y down or +Y up based on camera pitch)
		var v_dir := Vector3.UP if cam_fwd.y > 0.0 else Vector3.DOWN
		depth_dir = v_dir
		height_dir = Vector3(dominant_horiz_look)
		width_dir = depth_dir.cross(height_dir)
	else:
		# Horizontal mode: Depth extends along ground plane in look direction, Height is +Y (Up)
		depth_dir = Vector3(dominant_horiz_look)
		height_dir = Vector3.UP
		width_dir = depth_dir.cross(height_dir)
	
	# Calculate Box Size along world axes.
	var box_size := Vector3(
		absf(float(width) * width_dir.x + float(height) * height_dir.x + float(depth) * depth_dir.x),
		absf(float(width) * width_dir.y + float(height) * height_dir.y + float(depth) * depth_dir.y),
		absf(float(width) * width_dir.z + float(height) * height_dir.z + float(depth) * depth_dir.z)
	)
	
	# Alternating Right/Left width extension calculation.
	var left_ext: float = float((width - 1) / 2)
	var right_ext: float = float(width - 1) - left_ext
	var width_offset: float = (right_ext - left_ext) * 0.5
	
	# Calculate Box Center.
	var base_center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var box_center: Vector3 = base_center + depth_dir * ((float(depth) - 1.0) * 0.5) + height_dir * ((float(height) - 1.0) * 0.5) + width_dir * width_offset
	
	# Save frame state for commit
	_has_valid_target = true
	_last_cell = cell
	_last_depth_dir = depth_dir
	_last_height_dir = height_dir
	_last_width_dir = width_dir
	_last_box_center = box_center
	_last_box_size = box_size
	
	_ghost.show_box_at(box_center, box_size, true)


## Confirm designation on LMB click: filters terrain voxel coordinates and places persistent visual markers.
func _try_commit_designation() -> void:
	if not _has_valid_target:
		return
	
	var coords: Array[Vector3i] = []
	var left_ext: int = int((width - 1) / 2)
	var right_ext: int = int(width - 1) - left_ext
	
	for d_idx: int in range(depth):
		for h_idx: int in range(height):
			for w_idx: int in range(-left_ext, right_ext + 1):
				var offset_v := Vector3(
					float(d_idx) * _last_depth_dir.x + float(h_idx) * _last_height_dir.x + float(w_idx) * _last_width_dir.x,
					float(d_idx) * _last_depth_dir.y + float(h_idx) * _last_height_dir.y + float(w_idx) * _last_width_dir.y,
					float(d_idx) * _last_depth_dir.z + float(h_idx) * _last_height_dir.z + float(w_idx) * _last_width_dir.z
				)
				var v_cell := Vector3i(
					_last_cell.x + int(round(offset_v.x)),
					_last_cell.y + int(round(offset_v.y)),
					_last_cell.z + int(round(offset_v.z))
				)
				if not coords.has(v_cell):
					coords.append(v_cell)
	
	# Filter to only voxels that actually contain terrain
	var terrain_coords: Array[Vector3i] = filter_terrain_voxels(coords)
	
	# 1. Output marked terrain coordinates to stdout
	print("[Dig Designation] Marked %d terrain voxels for digging (out of %d in box): %s" % [
		terrain_coords.size(),
		coords.size(),
		str(terrain_coords)
	])
	
	# 2. Add entry to game log HUD
	if terrain_coords.is_empty():
		GameLog.info("No terrain in designated area")
	else:
		GameLog.info("Marked %d blocks for digging" % terrain_coords.size())
		# 3. Spawn persistent amber ghost markers on each solid terrain block
		_spawn_designation_markers(terrain_coords)
		# 4. Emit signal for listeners
		EventBus.dig_box_designated.emit(terrain_coords)


## Returns true if cell contains solid terrain (either blocky voxel or smooth terrain meeting the height threshold).
func is_terrain_at(cell: Vector3i) -> bool:
	if grid_adapter == null:
		return false
	
	# 1. Check blocky grid
	if grid_adapter.get_block_at(cell) != "":
		return true
	
	# 2. Check smooth terrain grid with height threshold
	var smooth: SmoothGrid = grid_adapter.get_smooth_grid()
	if smooth != null:
		var h: float = smooth.height_at(float(cell.x) + 0.5, float(cell.z) + 0.5)
		if not is_nan(h):
			return h >= (float(cell.y) + terrain_solidity_threshold)
		
		# Fallback if height_at returns NaN: check VoxelTool SDF value
		var vt: VoxelTool = smooth.get_voxel_tool()
		if vt != null:
			return vt.get_voxel_f(cell) <= -terrain_solidity_threshold
	
	return false


## Filters an array of voxel coordinates to return only those containing actual terrain.
func filter_terrain_voxels(coords: Array[Vector3i]) -> Array[Vector3i]:
	var terrain_coords: Array[Vector3i] = []
	for cell in coords:
		if is_terrain_at(cell):
			terrain_coords.append(cell)
	return terrain_coords


## Spawns persistent translucent amber marker boxes over each designated terrain cell.
func _spawn_designation_markers(cells: Array[Vector3i]) -> void:
	var container := _get_or_create_marker_container()
	if container == null:
		return
	
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE
	
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.65, 0.15, 0.35) # Translucent Amber / Orange
	mat.render_priority = 5
	
	for cell in cells:
		var cell_name := "Marker_%d_%d_%d" % [cell.x, cell.y, cell.z]
		if container.has_node(cell_name):
			continue
		
		var marker := MeshInstance3D.new()
		marker.name = cell_name
		marker.mesh = box_mesh
		marker.global_position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		marker.material_override = mat
		container.add_child(marker)


func _get_or_create_marker_container() -> Node3D:
	var root: Node = get_parent()
	if root == null:
		root = self
	var container := root.get_node_or_null("DesignationContainer") as Node3D
	if container == null:
		container = Node3D.new()
		container.name = "DesignationContainer"
		root.add_child(container)
	return container


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



## Called when a colonist completes a dig job at a cell: removes visual marker and carves terrain.
func _on_dig_job_completed(cell: Vector3i) -> void:
	var container := _get_or_create_marker_container()
	if container != null:
		var cell_name := "Marker_%d_%d_%d" % [cell.x, cell.y, cell.z]
		var marker := container.get_node_or_null(cell_name)
		if marker != null:
			marker.queue_free()

	if grid_adapter != null:
		grid_adapter.remove_block_at(cell)
		var smooth: SmoothGrid = grid_adapter.get_smooth_grid()
		if smooth != null:
			smooth.carve_box(Vector3(cell), Vector3(cell) + Vector3.ONE)
