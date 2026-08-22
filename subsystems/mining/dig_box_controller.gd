class_name DigBoxController
extends Node3D
## Controller for Dig Box & Stairway Designation mode (ARCH "Mining / Designation").
##
## Active when Player.mode == DIG_BOX_DESIGNATION. Casts a screen-center raycast
## onto natural smooth terrain or blocky terrain.
##
## Orientation modes (cycled with RMB):
##   - HORIZONTAL: Depth along ground plane N/S/E/W, Height +Y
##   - VERTICAL: Depth down -Y or up +Y, Height along ground plane
##   - STAIRWAY_DOWN: Descending staircase (2 wide x 3 high), advancing downward
##     along the dominant horizontal view direction.
##
## Resizing controls:
##   - Scroll Wheel:
##       - In Horizontal / Vertical: Width +/- 1 (clamped 1..11, alternating R/L)
##       - In Stairway Down: Steps / Length +/- 1 (clamped 1..11)
##   - Shift + Scroll: Depth +/- 1 (clamped 1..11)
##   - Ctrl + Scroll: Height +/- 1 (clamped 1..11)
##
## Designation:
##   - LMB: Filters all coordinates that actually contain terrain blocks, logs
##     the coordinates, and emits EventBus.dig_box_designated.

enum OrientationMode {
	HORIZONTAL,
	VERTICAL,
	STAIRWAY_DOWN,
}

const _RAY_DISTANCE := 30.0

# Runtime-wired dependencies
var grid_adapter: VoxelGridAdapter
var exclude_bodies: Array[PhysicsBody3D] = []

@export var camera_path: NodePath = ^""

var width: int = 1
var height: int = 3
var depth: int = 3
var mode: OrientationMode = OrientationMode.HORIZONTAL

var is_vertical: bool:
	get:
		return mode == OrientationMode.VERTICAL
	set(val):
		mode = OrientationMode.VERTICAL if val else OrientationMode.HORIZONTAL

## Minimum fraction of a voxel cell's height (0.0 to 1.0) that must be solid ground to be marked.
## 0.5 means the terrain surface must reach at least the middle of the cell (Y + 0.5).
@export_range(0.0, 1.0, 0.05) var terrain_solidity_threshold: float = 0.5

var _ghost: GhostPreview
var _camera: Camera3D
var _active: bool = false

# Last calculated frame state
var _has_valid_target: bool = false
var _last_cell: Vector3i = Vector3i.ZERO
var _last_dominant_horiz_look: Vector3i = Vector3i.FORWARD
var _last_depth_dir: Vector3 = Vector3.ZERO
var _last_height_dir: Vector3 = Vector3.ZERO
var _last_width_dir: Vector3 = Vector3.ZERO
var _last_box_center: Vector3 = Vector3.ZERO
var _last_box_size: Vector3
# Cache variables to avoid expensive mesh regeneration every frame
var _last_rendered_cell := Vector3i.MAX
var _last_rendered_look := Vector3i.MAX
var _last_rendered_depth_dir := Vector3.ZERO
var _last_rendered_height_dir := Vector3.ZERO
var _last_rendered_width_dir := Vector3.ZERO
var _last_rendered_mode := -1
var _last_rendered_width := -1
var _last_rendered_height := -1
var _last_rendered_depth := -1


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
	if not _active:
		if _ghost != null:
			_ghost.hide_()
		_has_valid_target = false


func _on_dig_box_toggled(active: bool) -> void:
	set_active(active)
	if active:
		mode = OrientationMode.HORIZONTAL
		width = 1
		height = 3
		depth = 3
		EventBus.dig_box_mode_changed.emit(get_mode_name())
		EventBus.dig_box_dimensions_changed.emit(width, height, depth)


## Cycle between Horizontal, Vertical, and Stairway Down modes.
func cycle_mode() -> void:
	mode = ((int(mode) + 1) % 3) as OrientationMode
	if mode == OrientationMode.STAIRWAY_DOWN:
		width = 2
		height = 3
	EventBus.dig_box_mode_changed.emit(get_mode_name())
	EventBus.dig_box_dimensions_changed.emit(width, height, depth)


func get_mode_name() -> String:
	match mode:
		OrientationMode.HORIZONTAL:
			return "Horizontal"
		OrientationMode.VERTICAL:
			return "Vertical"
		OrientationMode.STAIRWAY_DOWN:
			return "Stairway (Down)"
		_:
			return "Horizontal"


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
		
		# Right-click cycles between Horizontal, Vertical, and Stairway modes
		if btn == MOUSE_BUTTON_RIGHT:
			cycle_mode()
			get_viewport().set_input_as_handled()
			return
		
		var is_wheel: bool = btn in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
		if not is_wheel:
			return
		
		var changed := false
		
		if mode == OrientationMode.STAIRWAY_DOWN:
			# In Stairway mode, width is fixed to 2 and height is fixed to 3.
			# Any wheel action adjusts depth (number of steps).
			if btn in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_RIGHT]:
				var new_d := clampi(depth + 1, 1, 11)
				if new_d != depth:
					depth = new_d
					changed = true
			elif btn in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT]:
				var new_d := clampi(depth - 1, 1, 11)
				if new_d != depth:
					depth = new_d
					changed = true
		else:
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
	
	_has_valid_target = true
	_last_cell = cell
	_last_dominant_horiz_look = dominant_horiz_look
	
	var depth_dir: Vector3
	var height_dir: Vector3
	var width_dir: Vector3
	
	if mode == OrientationMode.VERTICAL:
		var v_dir := Vector3.UP if cam_fwd.y > 0.0 else Vector3.DOWN
		depth_dir = v_dir
		height_dir = Vector3(dominant_horiz_look)
		width_dir = depth_dir.cross(height_dir)
	else:
		depth_dir = Vector3(dominant_horiz_look)
		height_dir = Vector3.UP
		width_dir = depth_dir.cross(height_dir)
	
	# Save frame state for commit
	_last_depth_dir = depth_dir
	_last_height_dir = height_dir
	_last_width_dir = width_dir
	
	# Check cache: avoid rebuilding meshes if target parameters haven't changed
	if (cell == _last_rendered_cell and
		dominant_horiz_look == _last_rendered_look and
		depth_dir == _last_rendered_depth_dir and
		height_dir == _last_rendered_height_dir and
		width_dir == _last_rendered_width_dir and
		mode == _last_rendered_mode and
		width == _last_rendered_width and
		height == _last_rendered_height and
		depth == _last_rendered_depth):
		return
	
	_last_rendered_cell = cell
	_last_rendered_look = dominant_horiz_look
	_last_rendered_depth_dir = depth_dir
	_last_rendered_height_dir = height_dir
	_last_rendered_width_dir = width_dir
	_last_rendered_mode = mode
	_last_rendered_width = width
	_last_rendered_height = height
	_last_rendered_depth = depth
	
	# Get all candidate coordinates for the active shape
	var all_coords: Array[Vector3i]
	if mode == OrientationMode.STAIRWAY_DOWN:
		all_coords = get_stairway_coordinates(cell, dominant_horiz_look, depth)
	else:
		all_coords = get_box_coordinates(cell, depth_dir, height_dir, width_dir, width, height, depth)
	
	var solid_cells: Array[Vector3i] = []
	var air_cells: Array[Vector3i] = []
	for c in all_coords:
		if is_terrain_at(c):
			solid_cells.append(c)
		else:
			air_cells.append(c)
	
	var solid_mesh := build_cells_solid_mesh(solid_cells, cell)
	var wire_mesh := build_cells_wire_mesh(air_cells, cell)
	
	_ghost.show_split_at(Vector3(cell), solid_mesh, wire_mesh, true)


## Confirm designation on LMB click: filters terrain voxel coordinates and places persistent visual markers.
func _try_commit_designation() -> void:
	if not _has_valid_target:
		return
	
	var coords: Array[Vector3i] = []
	
	if mode == OrientationMode.STAIRWAY_DOWN:
		coords = get_stairway_coordinates(_last_cell, _last_dominant_horiz_look, depth)
	else:
		coords = get_box_coordinates(_last_cell, _last_depth_dir, _last_height_dir, _last_width_dir, width, height, depth)
	
	# Filter to only voxels that actually contain terrain
	var terrain_coords: Array[Vector3i] = filter_terrain_voxels(coords)
	
	# 1. Output marked terrain coordinates to stdout
	print("[Dig Designation] Marked %d terrain voxels for digging (%s, out of %d in shape): %s" % [
		terrain_coords.size(),
		get_mode_name(),
		coords.size(),
		str(terrain_coords)
	])
	
	# 2. Add entry to game log HUD
	if terrain_coords.is_empty():
		GameLog.info("No terrain in designated area")
	else:
		GameLog.info("Marked %d blocks for digging" % terrain_coords.size())
		EventBus.dig_box_designated.emit(terrain_coords)


## Returns true if cell contains natural smooth terrain meeting the height threshold.
func is_terrain_at(cell: Vector3i) -> bool:
	if grid_adapter == null:
		return false
	return grid_adapter.is_terrain_at(cell, terrain_solidity_threshold)


## Filters an array of voxel coordinates to return only those containing actual terrain.
func filter_terrain_voxels(coords: Array[Vector3i]) -> Array[Vector3i]:
	var terrain_coords: Array[Vector3i] = []
	for cell in coords:
		if is_terrain_at(cell):
			terrain_coords.append(cell)
	return terrain_coords


## Calculates all voxel cells for a cuboid box designation.
static func get_box_coordinates(start_cell: Vector3i, depth_dir: Vector3, height_dir: Vector3, width_dir: Vector3, w: int, h: int, d: int) -> Array[Vector3i]:
	var coords: Array[Vector3i] = []
	var left_ext: int = int((w - 1) / 2)
	var right_ext: int = int(w - 1) - left_ext
	
	for d_idx: int in range(d):
		for h_idx: int in range(h):
			for w_idx: int in range(-left_ext, right_ext + 1):
				var offset_v := Vector3(
					float(d_idx) * depth_dir.x + float(h_idx) * height_dir.x + float(w_idx) * width_dir.x,
					float(d_idx) * depth_dir.y + float(h_idx) * height_dir.y + float(w_idx) * width_dir.y,
					float(d_idx) * depth_dir.z + float(h_idx) * height_dir.z + float(w_idx) * width_dir.z
				)
				var v_cell := Vector3i(
					start_cell.x + int(round(offset_v.x)),
					start_cell.y + int(round(offset_v.y)),
					start_cell.z + int(round(offset_v.z))
				)
				if not coords.has(v_cell):
					coords.append(v_cell)
	return coords


## Generate coordinates for a 2-wide x 3-high downward stairway tunnel.
static func get_stairway_coordinates(start_cell: Vector3i, dominant_horiz_look: Vector3i, steps: int) -> Array[Vector3i]:
	var coords: Array[Vector3i] = []
	var width_dir_v := Vector3(dominant_horiz_look).cross(Vector3.UP)
	var width_dir := Vector3i(int(round(width_dir_v.x)), int(round(width_dir_v.y)), int(round(width_dir_v.z)))
	
	for s: int in range(steps):
		for h: int in range(3):
			for w: int in range(2):
				var v_cell: Vector3i = start_cell + s * dominant_horiz_look + (h - s) * Vector3i.UP + w * width_dir
				if not coords.has(v_cell):
					coords.append(v_cell)
	return coords


## Build an ArrayMesh representing the multi-step staircase ghost preview.
static func build_stairway_mesh(steps: int, dominant_horiz_look: Vector3i) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var width_dir_v := Vector3(dominant_horiz_look).cross(Vector3.UP)
	var w_dir_i := Vector3i(int(round(width_dir_v.x)), int(round(width_dir_v.y)), int(round(width_dir_v.z)))
	
	var step_size := Vector3(
		absf(float(dominant_horiz_look.x)) + 2.0 * absf(width_dir_v.x),
		3.0,
		absf(float(dominant_horiz_look.z)) + 2.0 * absf(width_dir_v.z)
	)
	var box_mesh := BoxMesh.new()
	box_mesh.size = step_size
	
	for s: int in range(steps):
		var step_center := Vector3(dominant_horiz_look) * float(s) + Vector3(w_dir_i) * 0.5 + Vector3(0.5, 1.5 - float(s), 0.5)
		st.append_from(box_mesh, 0, Transform3D(Basis(), step_center))
	
	return st.commit()


## Builds a solid triangle mesh from an array of cells relative to the origin cell.
static func build_cells_solid_mesh(cells: Array[Vector3i], origin: Vector3i) -> ArrayMesh:
	if cells.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.1, 1.1, 1.1)
	
	for cell in cells:
		var local_offset := Vector3(cell - origin) + Vector3(0.5, 0.5, 0.5)
		st.append_from(box_mesh, 0, Transform3D(Basis(), local_offset))
	return st.commit()


## Builds a 3D wireframe mesh from an array of cells relative to the origin cell (fast direct array generation).
static func build_cells_wire_mesh(cells: Array[Vector3i], origin: Vector3i, thickness: float = 0.02) -> ArrayMesh:
	var n := cells.size()
	if n == 0:
		return null
	
	# 12 beams per cell, each beam is a box with 24 vertices and 36 indices
	var vertices := PackedVector3Array()
	vertices.resize(n * 288)
	var indices := PackedInt32Array()
	indices.resize(n * 432)
	
	var half_t: float = thickness * 0.5
	var edge_h: float = 1.0 - half_t
	
	var v_offset := 0
	var i_offset := 0
	
	for cell in cells:
		var p := Vector3(cell - origin)
		
		# 12 Beam centers and extents
		# 4 X-beams (extent along X: 0.5, half-thickness in Y and Z)
		var beams: Array[Transform3D] = [
			Transform3D(Basis().scaled(Vector3(1.0, thickness, thickness)), p + Vector3(0.5, half_t, half_t)),
			Transform3D(Basis().scaled(Vector3(1.0, thickness, thickness)), p + Vector3(0.5, half_t, edge_h)),
			Transform3D(Basis().scaled(Vector3(1.0, thickness, thickness)), p + Vector3(0.5, edge_h, half_t)),
			Transform3D(Basis().scaled(Vector3(1.0, thickness, thickness)), p + Vector3(0.5, edge_h, edge_h)),
			# 4 Y-beams
			Transform3D(Basis().scaled(Vector3(thickness, 1.0, thickness)), p + Vector3(half_t, 0.5, half_t)),
			Transform3D(Basis().scaled(Vector3(thickness, 1.0, thickness)), p + Vector3(edge_h, 0.5, half_t)),
			Transform3D(Basis().scaled(Vector3(thickness, 1.0, thickness)), p + Vector3(half_t, 0.5, edge_h)),
			Transform3D(Basis().scaled(Vector3(thickness, 1.0, thickness)), p + Vector3(edge_h, 0.5, edge_h)),
			# 4 Z-beams
			Transform3D(Basis().scaled(Vector3(thickness, thickness, 1.0)), p + Vector3(half_t, half_t, 0.5)),
			Transform3D(Basis().scaled(Vector3(thickness, thickness, 1.0)), p + Vector3(edge_h, half_t, 0.5)),
			Transform3D(Basis().scaled(Vector3(thickness, thickness, 1.0)), p + Vector3(half_t, edge_h, 0.5)),
			Transform3D(Basis().scaled(Vector3(thickness, thickness, 1.0)), p + Vector3(edge_h, edge_h, 0.5))
		]
		
		for t in beams:
			var basis := t.basis * 0.5
			var origin_pos := t.origin
			
			# 8 local cube corners transformed
			var c0 := origin_pos + basis * Vector3(-1, -1, -1)
			var c1 := origin_pos + basis * Vector3( 1, -1, -1)
			var c2 := origin_pos + basis * Vector3( 1,  1, -1)
			var c3 := origin_pos + basis * Vector3(-1,  1, -1)
			var c4 := origin_pos + basis * Vector3(-1, -1,  1)
			var c5 := origin_pos + basis * Vector3( 1, -1,  1)
			var c6 := origin_pos + basis * Vector3( 1,  1,  1)
			var c7 := origin_pos + basis * Vector3(-1,  1,  1)
			
			# 6 faces
			var beam_verts: Array[Vector3] = [
				c4, c5, c6, c7, # Front (+Z)
				c1, c0, c3, c2, # Back (-Z)
				c7, c6, c2, c3, # Top (+Y)
				c0, c1, c5, c4, # Bottom (-Y)
				c5, c1, c2, c6, # Right (+X)
				c0, c4, c7, c3  # Left (-X)
			]
			
			for i in range(24):
				vertices[v_offset + i] = beam_verts[i]
			
			for f in range(6):
				var base_v: int = v_offset + f * 4
				indices[i_offset + f * 6 + 0] = base_v + 0
				indices[i_offset + f * 6 + 1] = base_v + 1
				indices[i_offset + f * 6 + 2] = base_v + 2
				indices[i_offset + f * 6 + 3] = base_v + 0
				indices[i_offset + f * 6 + 4] = base_v + 2
				indices[i_offset + f * 6 + 5] = base_v + 3
			
			v_offset += 24
			i_offset += 36
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
