class_name MapEditor
extends Node3D
## Standalone WYSIWYG dual-voxel map authoring environment.
##
## Loads both blocky structures and smooth Transvoxel terrain at runtime,
## providing fly-camera navigation, WYSIWYG visual verification, block/terrain
## sculpting, furniture authoring, spawn point management, undo history,
## grid overlay, and map lifecycle.

const EditorHUDClass = preload("res://tools/map_editor/editor_hud.gd")
const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")
const EditorGridOverlayClass = preload("res://tools/map_editor/editor_grid_overlay.gd")
const FurnitureAuthoringClass = preload("res://addons/voxel_paint/furniture_authoring.gd")
const StructureToolClass = preload("res://tools/map_editor/structure_tool.gd")

const MAPS_DIR: String = "res://data/maps/"
const TERRAIN_DIR: String = "res://data/terrain/"
const TEMPLATE_PATH: String = "res://subsystems/maps/map_template.tscn"
const DEFAULT_TERRAIN_GEN: String = "res://data/terrain/default_ground.tres"

const FLY_SPEED: float = 8.0
const FLY_SPEED_FAST: float = 20.0
const MOUSE_SENSITIVITY: float = 0.2

## Maximum number of undo operations in history.
const MAX_UNDO_DEPTH: int = 50

## Largest brush edge length B+scroll can reach in block mode.
const MAX_BRUSH_DIAMETER: int = 11
## Min/max sculpt radius for smooth terrain mode.
const MIN_SCULPT_RADIUS: float = 0.5
const MAX_SCULPT_RADIUS: float = 5.0
const SPAWN_REMOVE_RANGE: float = 4.0

## MapDef properties whose HUD metadata key has the same name.
const METADATA_KEYS: Array[String] = [
	"display_name", "description", "map_type", "difficulty",
	"flora_spawns_per_day", "flora_spawn_cap", "flora_max_spawn_attempts",
]


enum Mode {
	NAVIGATE,
	BLOCK,
	TERRAIN,
	FURNITURE,
	SPAWN,
	STRUCTURE,
}

var _mode: Mode = Mode.NAVIGATE
var _map_root: Map = null
var _map_def: MapDef = null
var _map_scene_path: String = ""

var _camera: Camera3D = null
var _viewer: VoxelViewer = null
var _hud: EditorHUD = null
var _launcher: EditorLauncher = null
var _grid_overlay: MeshInstance3D = null
var _exit_dialog: ConfirmationDialog = null
var _delete_dialog: ConfirmationDialog = null
var _unsaved_dialog: ConfirmationDialog = null
## The reload action waiting on the unsaved-changes dialog; invalid when none is.
var _pending_after_guard: Callable = Callable()
var _pending_delete_map_id: String = ""
var _drawer_file_dialog: FileDialog = null
var _dirty: bool = false
var _undo_stack: Array[Dictionary] = []

var _blocky_grid: BlockyGrid = null
var _block_vt: VoxelTool = null
var _block_library: BlockLibrary = null
var _selected_block_index: int = -1 # Resolved by id in _ready; indices shift with the block set
var _active_rotation_index: int = 0
var _brush_diameter: int = 1 # Brush edge length in blocks (B+scroll)

enum RotationAxis {
	Y = 0, # Yaw (Vector3.UP)
	X = 1, # Pitch (Vector3.RIGHT)
	Z = 2, # Roll (Vector3.FORWARD)
}
var _active_rotation_axis: int = RotationAxis.Y

var _smooth_grid: SmoothGrid = null
var _smooth_vt: VoxelTool = null
var _sculpt_radius: float = 2.0
var _terrain_material_id: String = "ground"

var _furniture_auth: FurnitureAuthoring = null
var _furniture_defs: Array[FurnitureDef] = []
var _selected_furniture_idx: int = 0
var _structure_defs: Array[StructureDef] = []
var _selected_structure_idx: int = 0
var _structure_tool: StructureToolClass = null
var _yaw: int = 0 # Quarter turns (0..3)
var _spawn_markers: Dictionary = {"player": null, "colonists": [], "enemies": []}
var _selected_spawn_type: String = "player"

var _ghost: MeshInstance3D = null
var _ghost_mat: StandardMaterial3D = null
var _box_mesh: BoxMesh = null
var _sphere_mesh: SphereMesh = null
var _capsule_mesh: CapsuleMesh = null
var _axis_line: MeshInstance3D = null
var _axis_line_mat: StandardMaterial3D = null

var _cam_yaw: float = 0.0
var _cam_pitch: float = -30.0


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_ghost()
	_build_grid_overlay()
	_block_library = BlockLibrary.new()
	_selected_block_index = _default_block_index()
	_furniture_defs = EditorContentLoader.load_furniture_defs()
	_furniture_auth = FurnitureAuthoringClass.new()
	_structure_defs = EditorContentLoader.load_structure_defs()
	_structure_tool = StructureToolClass.new()
	_structure_tool.name = "StructureTool"
	add_child(_structure_tool)
	if not _structure_defs.is_empty():
		_structure_tool.set_active_structure(_structure_defs[0])

	_hud = EditorHUDClass.new()
	add_child(_hud)
	_hud.setup(self)
	_hud.block_selected.connect(_on_hud_block_selected)
	_hud.furniture_selected.connect(_on_hud_furniture_selected)
	_hud.structure_selected.connect(_on_hud_structure_selected)
	_hud.save_requested.connect(save_map)
	_hud.spawn_type_selected.connect(_on_spawn_type_selected)
	_hud.terrain_apply_requested.connect(_on_terrain_apply)
	_hud.terrain_pick_image_requested.connect(_on_terrain_pick_image)
	_hud.water_apply_requested.connect(_on_water_apply_requested)
	_hud.metadata_edited.connect(_mark_dirty)
	_hud.set_mode(_mode)
	_hud.hide()

	_launcher = EditorLauncherClass.new()
	add_child(_launcher)
	_launcher.map_selected.connect(load_map)
	_launcher.new_map_requested.connect(func(payload: Dictionary) -> void:
		create_new_map(payload)
	)
	_launcher.map_delete_requested.connect(_request_delete_map)
	_launcher.setup(_scan_maps())
	_launcher.setup_noise_defs(_scan_noise_defs(), DEFAULT_TERRAIN_GEN)
	_launcher.show_launcher()

	_setup_exit_dialog()
	_setup_delete_dialog()
	_setup_unsaved_dialog()


func _mark_dirty() -> void:
	_dirty = true
	# 1. Map Info: Refreshing HUD status to reflect modified unsaved changes state.
	_refresh_map_info()


func _refresh_map_info() -> void:
	## Auxiliary: Updates map title and dirty state in the HUD.
	if _hud != null and _map_def != null:
		_hud.set_map_info(_map_def.id, _dirty)



## Default palette selection: first base block when present, else air (0).
## Indices shift whenever the block set changes, so the default resolves
## from the active base table rather than a hardcoded string.
func _default_block_index() -> int:
	var base := _block_library.get_base_indices()
	return base[0] if not base.is_empty() else 0


func _build_grid_overlay() -> void:
	_grid_overlay = EditorGridOverlayClass.create()
	add_child(_grid_overlay)
	_grid_overlay.visible = false


func _toggle_grid() -> void:
	if _grid_overlay == null:
		_build_grid_overlay()
	_grid_overlay.visible = not _grid_overlay.visible


func _push_undo(entry: Dictionary) -> void:
	_undo_stack.append(entry)
	if _undo_stack.size() > MAX_UNDO_DEPTH:
		_undo_stack.pop_front()


func _undo_last() -> void:
	if _undo_stack.is_empty() or _map_root == null:
		return
	var entry: Dictionary = _undo_stack.pop_back()
	# 1. Restore: the entry type decides which voxel layers are put back exactly as they were.
	match String(entry.get("type", "")):
		"block":
			_undo_block(entry)
		"terrain":
			_undo_terrain(entry)
		"structure":
			_undo_structure(entry)
		_:
			return
	# 2. Persist: both terrains flush so the restored state survives a reload.
	_flush_terrains()
	_mark_dirty()


func _undo_block(entry: Dictionary) -> void:
	## Auxiliary: Restores prior blocky voxel IDs.
	if _blocky_grid == null:
		return
	for op: Dictionary in entry.get("ops", []):
		_blocky_grid.set_raw_voxel(op["pos"], op["old_value"])


func _undo_terrain(entry: Dictionary) -> void:
	## Auxiliary: Restores smooth terrain snapshot.
	if _smooth_grid != null:
		_smooth_grid.restore_snapshot(entry.get("snapshot", {}))


func _undo_structure(entry: Dictionary) -> void:
	## Auxiliary: Restores structure placement blocks and terrain snapshot.
	var ops: Array = entry.get("ops", [])
	# 1. Blocks and air cells: put back, newest first, the raw voxel each op overwrote.
	for i in range(ops.size() - 1, -1, -1):
		_restore_structure_op(ops[i])
	# 2. Terrain: one exact restore replaces the old per-voxel inverse carves.
	if _smooth_grid != null:
		_smooth_grid.restore_snapshot(entry.get("terrain_snapshot", {}))


func _restore_structure_op(op: Dictionary) -> void:
	## Auxiliary: Restores a single structure block/air operation to prior raw voxel state.
	var op_type := String(op.get("type", ""))
	if _blocky_grid != null and (op_type == "block" or op_type == "air"):
		_blocky_grid.set_raw_voxel(op.get("pos", Vector3i.ZERO), int(op.get("old_raw", 0)))


func _flush_terrains() -> void:
	## Auxiliary: Persists modified blocks to sqlite streams on both voxel layers.
	if _map_root == null:
		return
	for terrain: VoxelTerrain in [_map_root.get_blocky_terrain(), _map_root.get_smooth_terrain()]:
		if terrain != null:
			terrain.save_modified_blocks()


func _input(event: InputEvent) -> void:
	# If launcher is open, ignore camera/edit input
	if _launcher != null and _launcher.visible:
		return

	# If any confirmation dialog is open, ignore camera/edit input
	if _modal_dialog_open():
		return

	# If search input or metadata in HUD is focused, handle Esc/Enter/Tab and let typing pass through
	if _hud != null and _hud.is_any_input_focused():
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER:
				_hud.unfocus_search()
				var focused := get_viewport().gui_get_focus_owner()
				if focused != null:
					focused.release_focus()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_TAB and _hud.is_search_focused():
				var dir := -1 if event.shift_pressed else 1
				if _mode == Mode.BLOCK:
					_cycle_block(dir)
					get_viewport().set_input_as_handled()
					return
				elif _mode == Mode.FURNITURE:
					_cycle_furniture(dir)
					get_viewport().set_input_as_handled()
				elif _mode == Mode.SPAWN:
					_cycle_spawn_type(dir)
					get_viewport().set_input_as_handled()
				elif _mode == Mode.STRUCTURE:
					_cycle_structure(dir)
					get_viewport().set_input_as_handled()
					return
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and mb.alt_pressed):
				if _mode == Mode.BLOCK:
					var hit := _raycast_from_camera()
					_do_block_pick(hit)
					get_viewport().set_input_as_handled()
					return
			if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					var hovered := get_viewport().gui_get_hovered_control()
					if hovered != null:
						return
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
					get_viewport().set_input_as_handled()
				elif mb.button_index == MOUSE_BUTTON_LEFT:
					if _mode == Mode.BLOCK:
						var hit := _raycast_from_camera()
						if mb.shift_pressed:
							_do_block_erase(hit)
						else:
							_do_block_paint(hit)
						get_viewport().set_input_as_handled()
					elif _mode == Mode.TERRAIN:
						var hit := _raycast_terrain()
						if mb.shift_pressed:
							_do_terrain_carve(hit)
						else:
							_do_terrain_add(hit)
						get_viewport().set_input_as_handled()
					elif _mode == Mode.FURNITURE:
						var hit := _raycast_from_camera()
						if mb.shift_pressed:
							_do_furniture_remove(hit)
						else:
							_do_furniture_place(hit)
						get_viewport().set_input_as_handled()
					elif _mode == Mode.SPAWN:
						var hit := _raycast_from_camera()
						if mb.shift_pressed or _selected_spawn_type == "remove":
							_do_spawn_remove(hit)
						else:
							_do_spawn_place(_selected_spawn_type, hit)
						get_viewport().set_input_as_handled()
					elif _mode == Mode.STRUCTURE:
						var hit := _raycast_from_camera()
						_do_structure_stamp(hit)
						get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				# 1. Viewport Routing: Allow hovered GUI controls (e.g. palettes) to scroll when cursor is uncaptured.
				if not _wheel_reaches_viewport():
					return
				var wheel_dir := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
				if Input.is_key_pressed(KEY_B):
					if _mode == Mode.BLOCK:
						_brush_diameter = clampi(_brush_diameter + wheel_dir, 1, MAX_BRUSH_DIAMETER)
					elif _mode == Mode.TERRAIN:
						_sculpt_radius = clampf(_sculpt_radius + float(wheel_dir) * 0.5, MIN_SCULPT_RADIUS, MAX_SCULPT_RADIUS)
					_update_hud_info()
					get_viewport().set_input_as_handled()
				elif _mode == Mode.BLOCK:
					_rotate_block_brush(_get_rotation_axis_vector(), (PI / 2.0) * float(wheel_dir))
					get_viewport().set_input_as_handled()
				elif _mode == Mode.FURNITURE:
					_do_furniture_rotate_step(wheel_dir)
					get_viewport().set_input_as_handled()
				elif _mode == Mode.STRUCTURE:
					if mb.ctrl_pressed:
						var step := 5 if mb.shift_pressed else 1
						if _structure_tool != null:
							_structure_tool.adjust_y_offset(wheel_dir * step)
							_update_structure_info()
					else:
						if _structure_tool != null:
							if wheel_dir > 0:
								_structure_tool.rotate_clockwise()
							else:
								_structure_tool.rotate_counter_clockwise()
							_update_structure_info()
					get_viewport().set_input_as_handled()

	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed:
			if k.keycode == KEY_ESCAPE:
				if _hud != null and _hud.is_terrain_drawer_visible():
					_hud.close_terrain_drawer()
					get_viewport().set_input_as_handled()
				elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					_request_exit()
			elif _mode == Mode.SPAWN and k.keycode == KEY_1:
				_set_spawn_type_direct("player")
				get_viewport().set_input_as_handled()
			elif _mode == Mode.SPAWN and k.keycode == KEY_2:
				_set_spawn_type_direct("colonist")
				get_viewport().set_input_as_handled()
			elif _mode == Mode.SPAWN and k.keycode == KEY_3:
				_set_spawn_type_direct("enemy")
				get_viewport().set_input_as_handled()
			elif _mode == Mode.SPAWN and k.keycode == KEY_4:
				_set_spawn_type_direct("remove")
				get_viewport().set_input_as_handled()
			elif k.keycode == KEY_F1:
				_set_mode(Mode.NAVIGATE)
			elif k.keycode == KEY_F2:
				_set_mode(Mode.BLOCK)
			elif k.keycode == KEY_F3:
				_set_mode(Mode.TERRAIN)
			elif k.keycode == KEY_F4:
				_set_mode(Mode.FURNITURE)
			elif k.keycode == KEY_F5:
				_set_mode(Mode.SPAWN)
			elif k.keycode == KEY_F6:
				_set_mode(Mode.STRUCTURE)
			elif k.keycode == KEY_G:
				_toggle_grid()
				get_viewport().set_input_as_handled()
			elif k.keycode == KEY_Z and k.ctrl_pressed:
				_undo_last()
				get_viewport().set_input_as_handled()
			elif k.keycode == KEY_BRACKETLEFT:
				if _mode == Mode.BLOCK:
					_cycle_block(-1)
				elif _mode == Mode.TERRAIN:
					_sculpt_radius = clampf(_sculpt_radius - 0.5, MIN_SCULPT_RADIUS, MAX_SCULPT_RADIUS)
					_update_hud_info()
				elif _mode == Mode.FURNITURE:
					_cycle_furniture(-1)
				elif _mode == Mode.STRUCTURE:
					_cycle_structure(-1)
			elif k.keycode == KEY_BRACKETRIGHT:
				if _mode == Mode.BLOCK:
					_cycle_block(1)
				elif _mode == Mode.TERRAIN:
					_sculpt_radius = clampf(_sculpt_radius + 0.5, MIN_SCULPT_RADIUS, MAX_SCULPT_RADIUS)
					_update_hud_info()
				elif _mode == Mode.FURNITURE:
					_cycle_furniture(1)
				elif _mode == Mode.STRUCTURE:
					_cycle_structure(1)
			elif k.keycode == KEY_TAB:
				var dir := -1 if k.shift_pressed else 1
				if _mode == Mode.BLOCK:
					_cycle_block(dir)
					get_viewport().set_input_as_handled()
				elif _mode == Mode.FURNITURE:
					_cycle_furniture(dir)
					get_viewport().set_input_as_handled()
				elif _mode == Mode.SPAWN:
					_cycle_spawn_type(dir)
					get_viewport().set_input_as_handled()
				elif _mode == Mode.STRUCTURE:
					_cycle_structure(dir)
					get_viewport().set_input_as_handled()
			elif k.keycode == KEY_R:
				if _mode == Mode.BLOCK or _mode == Mode.FURNITURE:
					_cycle_rotation_axis()
					get_viewport().set_input_as_handled()
				elif _mode == Mode.STRUCTURE:
					if _structure_tool != null:
						_structure_tool.rotate_clockwise()
						_update_structure_info()
					get_viewport().set_input_as_handled()
			elif (k.keycode == KEY_QUOTELEFT or k.keycode == KEY_SECTION or k.keycode == KEY_ASCIITILDE or (k.keycode == KEY_Z and not k.ctrl_pressed)) and _mode == Mode.BLOCK:
				_reset_block_rotation()
				get_viewport().set_input_as_handled()
			elif k.keycode == KEY_I and _mode == Mode.BLOCK:
				var hit := _raycast_from_camera()
				_do_block_pick(hit)
				get_viewport().set_input_as_handled()
			elif k.keycode == KEY_M and _mode == Mode.TERRAIN:
				_cycle_terrain_material(-1 if k.shift_pressed else 1)
				get_viewport().set_input_as_handled()
			elif _mode == Mode.STRUCTURE and (k.keycode == KEY_UP or k.keycode == KEY_DOWN or k.keycode == KEY_LEFT or k.keycode == KEY_RIGHT):
				var step := 5 if k.shift_pressed else 1
				var offset := Vector3i.ZERO
				if k.keycode == KEY_UP: offset.z -= step
				elif k.keycode == KEY_DOWN: offset.z += step
				elif k.keycode == KEY_LEFT: offset.x -= step
				elif k.keycode == KEY_RIGHT: offset.x += step
				if _structure_tool != null:
					_structure_tool.nudge(offset)
					_update_structure_info()
				get_viewport().set_input_as_handled()
			elif k.keycode == KEY_S and k.ctrl_pressed:
				save_map()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_cam_yaw -= mm.relative.x * MOUSE_SENSITIVITY
			_cam_pitch -= mm.relative.y * MOUSE_SENSITIVITY
			_cam_pitch = clampf(_cam_pitch, -89.0, 89.0)
			_apply_camera_rotation()


static func wheel_belongs_to_view(captured: bool, hovering_gui: bool) -> bool:
	return captured or not hovering_gui


func _wheel_reaches_viewport() -> bool:
	## Auxiliary: Determines if mouse wheel events should be handled by the 3D editor viewport.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var hovering_gui := get_viewport().gui_get_hovered_control() != null
	# 1. Routing check: Evaluate if wheel input belongs to viewport or GUI.
	return wheel_belongs_to_view(captured, hovering_gui)


func _apply_camera_rotation() -> void:
	if _camera != null:
		_camera.rotation_degrees = Vector3(_cam_pitch, _cam_yaw, 0.0)


func _process(delta: float) -> void:
	if _camera == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or (_hud != null and _hud.is_any_input_focused()):
		if _ghost != null:
			_ghost.visible = false
		if _hud != null:
			_hud.clear_coordinates()
		return

	if _mode == Mode.BLOCK:
		var hit := _raycast_from_camera()
		_update_ghost(hit)
		if _hud != null:
			if hit.get("hit", false):
				_hud.set_coordinates(_get_surface_hit_point(hit))
			else:
				_hud.clear_coordinates()
	elif _mode == Mode.TERRAIN:
		var hit := _raycast_terrain()
		_update_ghost(hit)
		if _hud != null:
			if hit.get("hit", false):
				_hud.set_coordinates(hit.get("point", Vector3.ZERO))
			else:
				_hud.clear_coordinates()
	elif _mode == Mode.FURNITURE:
		var hit := _raycast_from_camera()
		_update_ghost(hit)
		if _hud != null:
			if hit.get("hit", false):
				_hud.set_coordinates(_get_surface_hit_point(hit))
			else:
				_hud.clear_coordinates()
	elif _mode == Mode.SPAWN:
		var hit := _raycast_from_camera()
		_update_ghost(hit)
		if _hud != null:
			if hit.get("hit", false):
				_hud.set_coordinates(_get_surface_hit_point(hit))
			else:
				_hud.clear_coordinates()
	elif _mode == Mode.STRUCTURE:
		var hit := _raycast_from_camera()
		_update_ghost(hit)
		if _hud != null:
			if hit.get("hit", false):
				_hud.set_coordinates(_get_surface_hit_point(hit))
			else:
				_hud.clear_coordinates()
	else:
		if _ghost != null:
			_ghost.visible = false
		if _hud != null:
			var hit := _raycast_from_camera()
			if hit.get("hit", false):
				_hud.set_coordinates(_get_surface_hit_point(hit))
			else:
				_hud.clear_coordinates()

	var speed: float = FLY_SPEED_FAST if Input.is_key_pressed(KEY_SHIFT) else FLY_SPEED
	var forward: Vector3 = -_camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = _camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move += forward
	if Input.is_key_pressed(KEY_S): move -= forward
	if Input.is_key_pressed(KEY_D): move += right
	if Input.is_key_pressed(KEY_A): move -= right
	if Input.is_key_pressed(KEY_SPACE): move += Vector3.UP
	if Input.is_key_pressed(KEY_C): move += Vector3.DOWN

	if move != Vector3.ZERO:
		_camera.global_position += move.normalized() * speed * delta


func load_map(map_id: String, recapture_mouse: bool = true) -> void:
	var def_path := MAPS_DIR + map_id + "/map_def.tres"
	if not ResourceLoader.exists(def_path):
		push_error("MapEditor: map_def not found at '%s'" % def_path)
		return

	var def: MapDef = load(def_path) as MapDef
	if def == null:
		push_error("MapEditor: failed to load MapDef from '%s'" % def_path)
		return

	if _map_root != null:
		_map_root.queue_free()
		_map_root = null

	if not ResourceLoader.exists(def.scene_path):
		push_error("MapEditor: scene not found at '%s'" % def.scene_path)
		return

	var packed: PackedScene = load(def.scene_path) as PackedScene
	if packed == null:
		push_error("MapEditor: failed to load PackedScene '%s'" % def.scene_path)
		return

	var instance := packed.instantiate()
	_inject_terrain_gen(instance, def)
	if instance is Map and def != null:
		(instance as Map).set_world_bounds(def.world_bounds)
	add_child(instance)

	_map_root = instance as Map
	_map_def = def
	_map_scene_path = def.scene_path
	_dirty = false
	_undo_stack.clear()

	_blocky_grid = _map_root.blocky_grid
	if _blocky_grid != null:
		_block_vt = _blocky_grid.get_voxel_tool()
		_block_vt.mode = VoxelTool.MODE_SET

	# 1. Smooth Grid: Resolving active live smooth grid to confirm valid terrain generator exists.
	_smooth_grid = _resolve_live_smooth_grid()
	if _smooth_grid != null:
		_smooth_vt = _smooth_grid.get_voxel_tool()
		if _smooth_grid.default_material != null and not _smooth_grid.default_material.id.is_empty():
			_terrain_material_id = _smooth_grid.default_material.id
		else:
			_terrain_material_id = "ground"
	else:
		_smooth_vt = null
		_terrain_material_id = "ground"

	_attach_streams(_map_root, map_id)
	if _furniture_auth != null:
		_furniture_auth.bind(_map_root)
	_cache_spawn_markers()
	_position_camera_at_spawn()

	if _hud != null:
		_hud.populate_block_library(_block_library, _selected_block_index)
		_hud.populate_furniture_list(_furniture_defs, _selected_furniture_idx)
		_hud.populate_structure_list(_structure_defs, _selected_structure_idx)
		_hud.set_map_info(map_id, _dirty)
		_hud.set_metadata(
			def.display_name,
			def.description,
			def.map_type,
			def.difficulty,
			def.world_bounds,
			def.flora_spawns_per_day,
			def.flora_spawn_cap,
			def.flora_max_spawn_attempts
		)
		_hud.set_terrain_available(_smooth_grid != null)
		_hud.set_terrain_drawer_state(_map_def.terrain_gen)
		_hud.set_water_drawer_state(def.water_enabled, def.water_level)
		_hud.show()
		_update_hud_info()

	if _launcher != null:
		_launcher.hide_launcher()

	if recapture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## A SmoothGrid without terrain_gen has queued itself for deletion but is still a
## valid node on the load frame, so "exists" is not "will build terrain".
func _resolve_live_smooth_grid() -> SmoothGrid:
	var grid := _map_root.get_smooth_grid()
	if grid == null or not is_instance_valid(grid) or grid.terrain_gen == null:
		return null
	return grid


## Create + open a new map under data/maps/<map_id>/. `payload` is the
## launcher's create-form Dictionary (shape: EditorLauncher.new_map_requested).
func create_new_map(payload: Dictionary) -> String:
	var map_name := payload.get("map_id", "") as String
	var id_error := MapIdRules.validate(map_name)
	if not id_error.is_empty():
		push_warning("MapEditor: " + id_error)
		return ""

	var folder_path := MAPS_DIR + map_name + "/"
	if DirAccess.dir_exists_absolute(folder_path):
		push_warning("MapEditor: map '%s' already exists" % map_name)
		return ""

	var err := DirAccess.make_dir_recursive_absolute(folder_path.trim_suffix("/"))
	if err != OK:
		push_warning("MapEditor: failed to create folder '%s' (error %d)" % [map_name, err])
		return ""

	var tscn_path := folder_path + "map.tscn"
	var db_path := folder_path + "map.sqlite"
	_stamp_map_scene(TEMPLATE_PATH, tscn_path, db_path)
	_create_map_def(payload, folder_path, tscn_path)

	if _launcher != null:
		_launcher.setup(_scan_maps())

	load_map(map_name)

	return tscn_path


func unload_map() -> void:
	if _exit_dialog != null and _exit_dialog.visible:
		_exit_dialog.hide()
	if _delete_dialog != null and _delete_dialog.visible:
		_delete_dialog.hide()
	if _unsaved_dialog != null and _unsaved_dialog.visible:
		_unsaved_dialog.hide()

	if _dirty:
		push_warning("MapEditor: unloading with unsaved changes")

	if _furniture_auth != null:
		_furniture_auth.unbind()
	if _structure_tool != null:
		_structure_tool.hide_ghost()
	_spawn_markers = {"player": null, "colonists": [], "enemies": []}

	if _map_root != null:
		_map_root.queue_free()
		_map_root = null

	_map_def = null
	_map_scene_path = ""
	_dirty = false
	_undo_stack.clear()

	_blocky_grid = null
	_block_vt = null
	_smooth_grid = null
	_smooth_vt = null

	if _hud != null:
		_hud.hide()

	if _launcher != null:
		_launcher.setup(_scan_maps())
		_launcher.show_launcher()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _setup_exit_dialog() -> void:
	_exit_dialog = ConfirmationDialog.new()
	_exit_dialog.name = "ExitConfirmationDialog"
	_exit_dialog.title = "Exit Map Editor"
	_exit_dialog.dialog_text = "Are you sure you want to exit the map editor?\nAny unsaved changes will be lost."
	_exit_dialog.ok_button_text = "Exit"
	_exit_dialog.cancel_button_text = "Cancel"
	_exit_dialog.confirmed.connect(_on_exit_confirmed)
	add_child(_exit_dialog)


func _request_exit() -> void:
	if _exit_dialog != null:
		_exit_dialog.popup_centered()


func _on_exit_confirmed() -> void:
	unload_map()


func _setup_delete_dialog() -> void:
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.name = "DeleteMapConfirmationDialog"
	_delete_dialog.title = "Delete Map"
	_delete_dialog.ok_button_text = "Delete"
	_delete_dialog.cancel_button_text = "Cancel"
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	_delete_dialog.canceled.connect(_on_delete_canceled)
	add_child(_delete_dialog)


func _on_delete_canceled() -> void:
	_pending_delete_map_id = ""


func _request_delete_map(map_id: String) -> void:
	_pending_delete_map_id = map_id
	_delete_dialog.dialog_text = "Permanently delete map '%s'?\nThis action cannot be undone." % map_id
	_delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	var map_id := _pending_delete_map_id
	_pending_delete_map_id = ""
	if map_id.is_empty():
		return
	if _map_def != null and _map_def.id == map_id:
		unload_map()
	_delete_map(map_id)
	if _launcher != null:
		_launcher.setup(_scan_maps())


func _setup_unsaved_dialog() -> void:
	_unsaved_dialog = ConfirmationDialog.new()
	_unsaved_dialog.name = "UnsavedChangesDialog"
	_unsaved_dialog.title = "Unsaved Changes"
	_unsaved_dialog.dialog_text = "This action reloads the map from disk.\nSave your changes first?"
	_unsaved_dialog.ok_button_text = "Save and Continue"
	_unsaved_dialog.cancel_button_text = "Cancel"
	_unsaved_dialog.add_button("Discard and Continue", true, "discard")
	_unsaved_dialog.confirmed.connect(_on_unsaved_save_confirmed)
	_unsaved_dialog.canceled.connect(_on_unsaved_canceled)
	_unsaved_dialog.custom_action.connect(_on_unsaved_custom_action)
	add_child(_unsaved_dialog)


## Runs action now on a clean map; on a dirty one it asks first, because a reload
## rebuilds the scene from disk and unsaved markers and metadata would vanish.
func _guard_unsaved(action: Callable) -> void:
	if not _dirty:
		action.call()
		return
	_pending_after_guard = action
	_unsaved_dialog.popup_centered()


func _on_unsaved_save_confirmed() -> void:
	# A failed save must not continue into a reload that would discard the work.
	if not save_map():
		_pending_after_guard = Callable()
		return
	# 1. Action: Proceed with guarded action after successful save.
	_run_pending_guarded_action()


func _on_unsaved_custom_action(action: StringName) -> void:
	if action != &"discard":
		return
	_unsaved_dialog.hide()
	# 1. Action: Proceed with guarded action, discarding unsaved changes.
	_run_pending_guarded_action()


func _on_unsaved_canceled() -> void:
	_pending_after_guard = Callable()


func _run_pending_guarded_action() -> void:
	## Auxiliary: Executes the saved guarded callable and clears the pending reference.
	var action := _pending_after_guard
	_pending_after_guard = Callable()
	if action.is_valid():
		action.call()


func _modal_dialog_open() -> bool:
	## Auxiliary: Returns whether any confirmation dialog is currently open.
	for dialog: ConfirmationDialog in [_exit_dialog, _delete_dialog, _unsaved_dialog]:
		if dialog != null and dialog.visible:
			return true
	return false


## Remove the map directory and all its contents from disk. Returns false
## (with push_error) if the directory could not be found or cleaned up.
func _delete_map(map_id: String) -> bool:
	var dir_path := MAPS_DIR + map_id + "/"
	if not DirAccess.dir_exists_absolute(dir_path):
		push_error("MapEditor: cannot delete map '%s' — directory not found" % map_id)
		return false
	return _remove_dir_recursive(dir_path)


func _remove_dir_recursive(dir_path: String) -> bool:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("MapEditor: failed to open directory '%s'" % dir_path)
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full_path := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not _remove_dir_recursive(full_path):
				return false
		else:
			if DirAccess.remove_absolute(full_path) != OK:
				push_error("MapEditor: failed to remove file '%s'" % full_path)
				return false
		entry = dir.get_next()
	dir.list_dir_end()
	if DirAccess.remove_absolute(dir_path.trim_suffix("/")) != OK:
		push_error("MapEditor: failed to remove map directory '%s'" % dir_path)
		return false
	return true


func _scan_maps() -> Array[MapDef]:
	var results: Array[MapDef] = []
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		return results

	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and not entry.begins_with("."):
			var def_path := MAPS_DIR + entry + "/map_def.tres"
			if ResourceLoader.exists(def_path):
				var def := load(def_path) as MapDef
				if def != null:
					results.append(def)
		entry = dir.get_next()
	dir.list_dir_end()
	return results


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0.1, 0.12, 0.15)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.environment = env_res
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.9)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "EditorCamera"
	_camera.current = true
	_camera.position = Vector3(0.0, 10.0, 20.0)
	_apply_camera_rotation()
	add_child(_camera)

	_viewer = VoxelViewer.new()
	_viewer.name = "VoxelViewer"
	_viewer.requires_visuals = true
	_viewer.requires_collisions = true
	_camera.add_child(_viewer)


func _build_ghost() -> void:
	_box_mesh = BoxMesh.new()
	_sphere_mesh = SphereMesh.new()
	# Unit-radius sphere so scale matches the brush radius in metres.
	_sphere_mesh.radius = 1.0
	_sphere_mesh.height = 2.0
	_capsule_mesh = CapsuleMesh.new()
	_capsule_mesh.radius = 0.4
	_capsule_mesh.height = 1.8

	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_ghost = MeshInstance3D.new()
	_ghost.name = "GhostMesh"
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.025
	cylinder.bottom_radius = 0.025
	cylinder.height = 1.8
	cylinder.radial_segments = 12

	_axis_line_mat = StandardMaterial3D.new()
	_axis_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_axis_line_mat.no_depth_test = true
	_axis_line_mat.albedo_color = Color(0.2, 1.0, 0.2, 0.95)

	_axis_line = MeshInstance3D.new()
	_axis_line.name = "AxisLineVisualizer"
	_axis_line.mesh = cylinder
	_axis_line.material_override = _axis_line_mat
	_axis_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_axis_line.visible = false
	add_child(_axis_line)


func _position_camera_at_spawn() -> void:
	if _map_def != null:
		_camera.global_position = _map_def.player_spawn + Vector3(0.0, 2.0, 5.0)
	else:
		_camera.global_position = Vector3(0.0, 10.0, 20.0)
	_cam_yaw = 0.0
	_cam_pitch = -20.0
	_apply_camera_rotation()


func _stamp_map_scene(template_path: String, tscn_dest_path: String, db_dest_path: String) -> void:
	var template_packed: PackedScene = load(template_path) as PackedScene
	if template_packed == null:
		push_error("MapEditor: failed to load template '%s'" % template_path)
		return

	var instance := template_packed.instantiate()
	var blocky_grid: BlockyGrid = instance.find_child("BlockyGrid") as BlockyGrid
	if blocky_grid != null:
		var stream := VoxelStreamSQLite.new()
		stream.database_path = db_dest_path
		var vt: VoxelTerrain = blocky_grid.get_node_or_null("VoxelTerrain") as VoxelTerrain
		if vt != null:
			vt.stream = stream

	var packed := PackedScene.new()
	var err := packed.pack(instance)
	if err == OK:
		ResourceSaver.save(packed, tscn_dest_path)
	else:
		push_error("MapEditor: failed to pack scene for '%s' (error %d)" % [tscn_dest_path, err])
	instance.free()


func _create_map_def(payload: Dictionary, folder_path: String, tscn_path: String) -> void:
	var map_name := payload.get("map_id", "") as String
	# 1. Shell: identity, spawn, flora and bounds from the launcher payload.
	var def := _new_map_def_shell(payload, tscn_path)
	# 2. Terrain: noise copy, heightmap, or none, per the launcher's mode.
	def.terrain_gen = _build_initial_terrain_def(payload, map_name)
	# 3. Water: the same flags on MapDef and its (map-owned) terrain def.
	def.water_enabled = bool(payload.get("water_enabled", false))
	def.water_level = float(payload.get("water_level", -2.0))
	MapTerrainAuthoring.apply_water(def.terrain_gen, def.water_enabled, def.water_level)
	# 4. Persist the terrain def first so MapDef stores its ext_resource path.
	MapTerrainAuthoring.persist_owned(def.terrain_gen, MAPS_DIR, map_name)
	var err := ResourceSaver.save(def, folder_path + "map_def.tres")
	if err != OK:
		push_error("MapEditor: failed to save MapDef to '%s' (error %d)" % [folder_path + "map_def.tres", err])


func _build_initial_terrain_def(payload: Dictionary, map_name: String) -> TerrainGenDef:
	match int(payload.get("terrain_mode", EditorLauncherClass.TerrainMode.NOISE)):
		EditorLauncherClass.TerrainMode.NONE:
			# No terrain_gen: the SmoothGrid frees itself, a blocky-only map.
			return null
		EditorLauncherClass.TerrainMode.HEIGHTMAP:
			return _initial_heightmap_def(payload, map_name)
		_:
			return _initial_noise_def(payload, map_name)


func _new_map_def_shell(payload: Dictionary, tscn_path: String) -> MapDef:
	var map_name := payload.get("map_id", "") as String
	var def := MapDef.new()
	def.id = map_name
	def.display_name = map_name.capitalize()
	def.scene_path = tscn_path
	def.map_type = int(payload.get("map_type", MapDef.MapType.POI)) as MapDef.MapType
	def.player_spawn = Vector3(0, 5, 0)
	def.difficulty = 1
	if payload.get("world_bounds") is AABB:
		def.world_bounds = payload["world_bounds"]
	# Flora rate, cap, attempts and palette come from the launcher payload.
	_apply_flora_payload(def, payload)
	return def


func _apply_flora_payload(def: MapDef, payload: Dictionary) -> void:
	def.flora_spawns_per_day = int(payload.get("flora_spawns_per_day", 0))
	def.flora_spawn_cap = int(payload.get("flora_spawn_cap", 60))
	def.flora_max_spawn_attempts = int(payload.get("flora_max_spawn_attempts", 15))
	# Task 8.2 (MapEditorConfig) replaces this literal with the configured palette.
	var tree1_def := load("res://data/furniture/tree1.tres") as BuildableDef
	if tree1_def != null:
		def.flora_palette = [tree1_def]


func _initial_heightmap_def(payload: Dictionary, map_name: String) -> TerrainGenDef:
	var image: Image = payload.get("image", null)
	if image == null:
		push_error("MapEditor: heightmap map '%s' requested without an image - no terrain def written" % map_name)
		return null
	return MapTerrainAuthoring.build_heightmap_def(
		map_name,
		image,
		float(payload.get("height_start", MapTerrainAuthoring.DEFAULT_HEIGHT_START)),
		float(payload.get("height_range", MapTerrainAuthoring.DEFAULT_HEIGHT_RANGE)),
		bool(payload.get("snap_to_grid", false)),
	)


func _initial_noise_def(payload: Dictionary, map_name: String) -> TerrainGenDef:
	var noise_path := payload.get("noise_def_path", "") as String
	var source_path := noise_path if ResourceLoader.exists(noise_path) else DEFAULT_TERRAIN_GEN
	var shared: TerrainGenDef = load(source_path) as TerrainGenDef if ResourceLoader.exists(source_path) else null
	# A copy inside this map's folder, so its water flags and edits never touch the shared baseline.
	return MapTerrainAuthoring.ensure_map_owned(shared, map_name)


## Shared-def scan for the launcher's noise dropdown: data/terrain/*.tres minus
## heightmap-driven defs (those are per-map content, not shared baselines).
func _scan_noise_defs() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var dir := DirAccess.open(TERRAIN_DIR)
	if dir == null:
		return results
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.ends_with(".tres"):
			var path := TERRAIN_DIR + entry
			var terrain_def := load(path) as TerrainGenDef
			if terrain_def != null and terrain_def.heightmap == null:
				var def_id := terrain_def.id if not terrain_def.id.is_empty() else entry.get_basename()
				results.append({"id": def_id, "path": path})
		entry = dir.get_next()
	dir.list_dir_end()
	results.sort_custom(func(a: Dictionary, b: Dictionary): return a["id"] < b["id"])
	return results


## Write the per-map heightmap TerrainGenDef with an EMBEDDED ImageTexture: the
## editor is a runtime process and cannot run Godot's import pipeline, so a bare
## PNG copied into the project wouldn't load via ResourceLoader — embedding
## keeps the map folder self-contained and export-safe.
# --- terrain drawer -------------------------------------------------------------

func _on_terrain_apply() -> void:
	if _map_def == null or _hud == null:
		return
	# The apply rewrites defs and reloads the map, so unsaved scene edits get a chance to be saved first.
	_guard_unsaved(_apply_terrain_now)


func _apply_terrain_now() -> void:
	if _map_def == null or _hud == null:
		return
	var edits: Dictionary = _hud.get_terrain_drawer_edits()

	# 1. Terrain def: remove, replace image, or edit the map-owned def in memory, so a shared baseline is never mutated.
	_apply_terrain_edits(edits)
	# 2. Water: mirrored onto MapDef and the def together, so every apply path persists the same flags.
	_apply_water_edits(edits)
	# 3. Persist the def once (no-op when the map has no terrain).
	_persist_terrain_def()
	# 4. Persist MapDef so the reload below reads the new pointers.
	_save_map_def()
	# 5. One reload: generator, streams and drawer state rebuild from the saved defs.
	_reload_current_map()


func _apply_terrain_edits(edits: Dictionary) -> void:
	if bool(edits.get("remove", false)):
		_map_def.terrain_gen = null
		return
	var pending: Image = edits.get("pending_image", null)
	if pending != null:
		# Replace/convert always builds a fresh per-map heightmap def.
		_map_def.terrain_gen = _build_replacement_def(pending, edits)
		return
	if _map_def.terrain_gen == null:
		return
	# Localize a shared baseline into this map's folder before mutating it.
	_map_def.terrain_gen = MapTerrainAuthoring.ensure_map_owned(_map_def.terrain_gen, _map_def.id)
	MapTerrainAuthoring.apply_edits(_map_def.terrain_gen, edits)


func _build_replacement_def(image: Image, edits: Dictionary) -> TerrainGenDef:
	return MapTerrainAuthoring.build_heightmap_def(
		_map_def.id,
		image,
		float(edits.get("height_start", MapTerrainAuthoring.DEFAULT_HEIGHT_START)),
		float(edits.get("height_range", MapTerrainAuthoring.DEFAULT_HEIGHT_RANGE)),
		bool(edits.get("snap_to_grid", false)),
	)


func _apply_water_edits(edits: Dictionary) -> void:
	if edits.has("water_enabled"):
		_map_def.water_enabled = bool(edits["water_enabled"])
		_map_def.water_level = float(edits.get("water_level", _map_def.water_level))
	if _map_def.terrain_gen == null:
		return
	_map_def.terrain_gen = MapTerrainAuthoring.ensure_map_owned(_map_def.terrain_gen, _map_def.id)
	MapTerrainAuthoring.apply_water(_map_def.terrain_gen, _map_def.water_enabled, _map_def.water_level)


func _persist_terrain_def() -> void:
	if _map_def.terrain_gen == null:
		return
	MapTerrainAuthoring.persist_owned(_map_def.terrain_gen, MAPS_DIR, _map_def.id)


func _on_terrain_pick_image() -> void:
	if _drawer_file_dialog == null:
		_drawer_file_dialog = EditorLauncherClass.create_image_file_dialog()
		_drawer_file_dialog.file_selected.connect(_on_drawer_image_selected)
	if _drawer_file_dialog.get_parent() == null:
		add_child(_drawer_file_dialog)
	_drawer_file_dialog.popup_centered(Vector2i(900, 600))


func _on_drawer_image_selected(path: String) -> void:
	if _hud == null:
		return
	var image := EditorLauncherClass.load_heightmap_image(path)
	if image == null:
		push_warning("MapEditor: could not use '%s' as a heightmap" % path)
		return
	_hud.set_pending_heightmap_image(image)


func _reload_current_map() -> void:
	if _map_def == null:
		return
	if _map_root != null:
		_map_root.flush_voxel_streams()
	# The reload came from an open panel, so the cursor stays free.
	load_map(_map_def.id, false)


## The def on MapDef is the single source of truth: assigning null over a stale
## def embedded by an older save makes Remove Terrain stick.
func _inject_terrain_gen(map: Node, def: MapDef) -> void:
	if def == null or map == null:
		return
	var smooth := map.get_node_or_null("SmoothGrid") as SmoothGrid
	if smooth == null:
		smooth = map.find_child("SmoothGrid") as SmoothGrid
	if smooth == null:
		return
	smooth.terrain_gen = def.terrain_gen
	if def.terrain_gen != null:
		# Same catalog injection SceneManager does at runtime, so strata and dig previews match what players hit.
		smooth.set_material_catalog(BuildLibrary.get_terrain_materials())


func _attach_streams(map: Node, map_id: String) -> void:
	var m: Map = map as Map
	var blocky_terrain: VoxelTerrain = null
	var smooth_terrain: VoxelTerrain = null

	if m != null:
		blocky_terrain = m.get_blocky_terrain()
		smooth_terrain = m.get_smooth_terrain()

	# Fallback if map._ready hasn't populated @onready fields or non-Map node
	if blocky_terrain == null and map != null:
		blocky_terrain = map.get_node_or_null("BlockyGrid/VoxelTerrain") as VoxelTerrain
	if smooth_terrain == null and map != null:
		smooth_terrain = map.get_node_or_null("SmoothGrid/VoxelTerrain") as VoxelTerrain

	var map_dir := MAPS_DIR + map_id + "/"

	if blocky_terrain != null:
		var stream_path := map_dir + "map.sqlite"
		if blocky_terrain.stream is VoxelStreamSQLite:
			(blocky_terrain.stream as VoxelStreamSQLite).database_path = stream_path
		elif blocky_terrain.stream == null:
			var stream := VoxelStreamSQLite.new()
			stream.database_path = stream_path
			blocky_terrain.stream = stream

	if smooth_terrain != null:
		var stream_path := map_dir + "terrain.sqlite"
		if smooth_terrain.stream is VoxelStreamSQLite:
			(smooth_terrain.stream as VoxelStreamSQLite).database_path = stream_path
		elif smooth_terrain.stream == null:
			var stream := VoxelStreamSQLite.new()
			stream.database_path = stream_path
			smooth_terrain.stream = stream


func _set_mode(mode: Mode) -> void:
	_mode = mode
	if _hud != null:
		_hud.set_mode(_mode)
		if _mode == Mode.BLOCK:
			_hud.populate_block_library(_block_library, _selected_block_index)
		elif _mode == Mode.FURNITURE:
			_hud.populate_furniture_list(_furniture_defs, _selected_furniture_idx)
		elif _mode == Mode.STRUCTURE:
			_hud.populate_structure_list(_structure_defs, _selected_structure_idx)
			if not _structure_defs.is_empty() and _selected_structure_idx >= 0 and _selected_structure_idx < _structure_defs.size():
				if _structure_tool != null:
					_structure_tool.set_active_structure(_structure_defs[_selected_structure_idx])
		_update_hud_info()

	if _structure_tool != null:
		if _mode == Mode.STRUCTURE:
			_structure_tool.activate()
		else:
			_structure_tool.deactivate()

	if _ghost != null:
		_ghost.visible = false
	_hide_axis_line()


func _update_ghost(hit: Dictionary) -> void:
	if _ghost == null or _ghost_mat == null:
		return

	var is_erase := Input.is_key_pressed(KEY_SHIFT)

	if _mode == Mode.BLOCK:
		if not hit.get("hit", false):
			_ghost.visible = false
			_hide_axis_line()
			return
		var cell := _target_cell(hit, is_erase)
		if cell == Vector3i.MIN:
			_ghost.visible = false
			_hide_axis_line()
			return
		var cell_center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		var rot_basis := VoxelBlockEncoder.rot_index_to_basis(_active_rotation_index)
		var def: BlockDef = _block_library.get_def_by_index(_selected_block_index) if _block_library != null else null
		var eff_mesh: Mesh = def.get_mesh() if def != null else null
		if not is_erase and def != null and eff_mesh != null and _brush_diameter == 1:
			_ghost.mesh = eff_mesh
			var mesh_aabb := eff_mesh.get_aabb()
			var local_center := mesh_aabb.get_center()
			_ghost.global_position = cell_center - rot_basis * local_center
			_ghost.transform.basis = rot_basis
		else:
			_ghost.mesh = _box_mesh
			var bounds := _brush_box(cell)
			_ghost.global_position = _box_center(bounds)
			_ghost.transform.basis = rot_basis.scaled(Vector3(_brush_diameter, _brush_diameter, _brush_diameter))
		_ghost_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.5) if is_erase else Color(0.2, 0.8, 0.2, 0.5)
		_ghost.visible = true
		if not is_erase:
			_update_axis_line(cell_center)
		else:
			_hide_axis_line()

	elif _mode == Mode.TERRAIN:
		_hide_axis_line()
		if not hit.get("hit", false):
			_ghost.visible = false
			return
		_ghost.mesh = _sphere_mesh
		_ghost.global_position = hit.get("point", Vector3.ZERO)
		_ghost.scale = Vector3.ONE * _sculpt_radius
		_ghost.global_rotation = Vector3.ZERO
		_ghost_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.5) if is_erase else Color(0.2, 0.8, 0.4, 0.5)
		_ghost.visible = true

	elif _mode == Mode.FURNITURE:
		if _furniture_defs.is_empty() or _selected_furniture_idx < 0 or _selected_furniture_idx >= _furniture_defs.size():
			_ghost.visible = false
			_hide_axis_line()
			return
		var def := _furniture_defs[_selected_furniture_idx]
		var furn_mesh: Mesh = def.get_mesh() if def != null else null
		if def == null or furn_mesh == null or not hit.get("hit", false):
			_ghost.visible = false
			_hide_axis_line()
			return
		var anchor := _target_cell(hit, false)
		if anchor == Vector3i.MIN:
			_ghost.visible = false
			_hide_axis_line()
			return
		_ghost.mesh = furn_mesh
		_ghost.scale = Vector3.ONE
		var dims := FurnitureLayer.dimensions_of(def)
		var origin := FurnitureLayer.world_origin(anchor, dims, _yaw)
		_ghost.global_position = origin
		_ghost.global_rotation = Vector3(0, deg_to_rad(_yaw * 90), 0)
		_ghost_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.5) if is_erase else Color(0.4, 0.8, 1.0, 0.5)
		_ghost.visible = true
		if not is_erase:
			_update_axis_line(origin + Vector3(0, float(dims.y) * 0.5, 0))
		else:
			_hide_axis_line()

	elif _mode == Mode.SPAWN:
		_hide_axis_line()
		if not hit.get("hit", false):
			_ghost.visible = false
			return
		_ghost.mesh = _capsule_mesh
		_ghost.scale = Vector3.ONE
		var is_remove := Input.is_key_pressed(KEY_SHIFT) or _selected_spawn_type == "remove"
		var pos := _get_surface_hit_point(hit)
		_ghost.global_position = pos + Vector3(0, 0.9, 0)
		_ghost.global_rotation = Vector3.ZERO
		if is_remove:
			_ghost_mat.albedo_color = Color(1.0, 0.4, 0.1, 0.6)
		elif _selected_spawn_type == "player":
			_ghost_mat.albedo_color = Color(0.2, 1.0, 0.2, 0.5)
		elif _selected_spawn_type == "colonist":
			_ghost_mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5)
		elif _selected_spawn_type == "enemy":
			_ghost_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.5)
		else:
			_ghost_mat.albedo_color = Color(0.2, 1.0, 0.2, 0.5)
		_ghost.visible = true

	elif _mode == Mode.STRUCTURE:
		_hide_axis_line()
		_ghost.visible = false
		if not hit.get("hit", false) or _structure_tool == null or _structure_tool.get_active_structure() == null:
			if _structure_tool != null:
				_structure_tool.hide_ghost()
			return
		var cell := _target_cell(hit, false)
		if cell == Vector3i.MIN:
			if _structure_tool != null:
				_structure_tool.hide_ghost()
			return
		_structure_tool.update_ghost_position(cell)

	else:
		_hide_axis_line()
		_ghost.visible = false


func _raycast_from_camera() -> Dictionary:
	if _map_root == null or _blocky_grid == null or _camera == null:
		return {"position": Vector3i.ZERO, "normal": Vector3i.ZERO, "hit": false, "surface": ""}
	var viewport := get_viewport()
	if viewport == null:
		return {"position": Vector3i.ZERO, "normal": Vector3i.ZERO, "hit": false, "surface": ""}
	var center: Vector2 = viewport.size / 2
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	return _blocky_grid.raycast_to_voxel(origin, dir, 100.0)


func _raycast_terrain() -> Dictionary:
	if _map_root == null or _smooth_grid == null or _camera == null:
		return {"hit": false, "point": Vector3.ZERO, "normal": Vector3.ZERO}
	var viewport := get_viewport()
	if viewport == null:
		return {"hit": false, "point": Vector3.ZERO, "normal": Vector3.ZERO}
	var center: Vector2 = viewport.size / 2
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	var res := _smooth_grid.raycast_to_surface(origin, dir, 100.0)
	return {
		"hit": res.get("hit", false),
		"point": res.get("position", Vector3.ZERO),
		"normal": res.get("normal", Vector3.ZERO),
	}


## Derives the world-space surface hit point from a raycast hit dictionary.
func _get_surface_hit_point(hit: Dictionary) -> Vector3:
	if hit.has("smooth_point"):
		return hit["smooth_point"]
	var pos: Vector3i = hit.get("position", Vector3i.ZERO)
	var normal: Vector3i = hit.get("normal", Vector3i.ZERO)
	var center := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	if normal == Vector3i.UP:
		return Vector3(center.x, float(pos.y + 1), center.z)
	return center + Vector3(normal) * 0.5


## Cell a crosshair stroke would write, or Vector3i.MIN when the hit has no
## valid target. Used for blocky and furniture modes.
func _target_cell(hit: Dictionary, erase: bool) -> Vector3i:
	var surface: String = hit.get("surface", "")
	var pos: Vector3i = hit.get("position", Vector3i.ZERO)
	if surface == "blocky" or surface == "body":
		return pos if erase else pos + hit.get("normal", Vector3i.ZERO)
	if surface == "smooth":
		if erase:
			return Vector3i.MIN
		return pos
	return Vector3i.MIN


## Brush footprint in cells for one block stroke anchored on `cell`: returns
## [begin, end] with end inclusive, matching `do_box` in this build.
func _brush_box(cell: Vector3i) -> Array[Vector3i]:
	var back := (_brush_diameter - 1) / 2
	var begin := cell - Vector3i(back, back, back)
	var end := begin + Vector3i(_brush_diameter - 1, _brush_diameter - 1, _brush_diameter - 1)
	return [begin, end]


## Computes the world-space center of a brush box footprint.
func _box_center(bounds: Array[Vector3i]) -> Vector3:
	return (Vector3(bounds[0]) + Vector3(bounds[1])) * 0.5 + Vector3(0.5, 0.5, 0.5)


## Writes one block paint/erase stroke's full brush footprint and persists it.
func _apply_block_brush(cell: Vector3i, value: int) -> void:
	const MAX_RETRIES := 5
	const RETRY_DELAY := 0.1
	_block_vt.value = value
	var bounds := _brush_box(cell)

	for attempt in MAX_RETRIES:
		_block_vt.do_box(bounds[0], bounds[1])
		if _block_vt.get_voxel(cell) == value:
			_map_root.get_blocky_terrain().save_modified_blocks()
			_mark_dirty()
			return
		await Engine.get_main_loop().create_timer(RETRY_DELAY).timeout

	push_warning("MapEditor: block write at %s did not land after %d retries" % [str(cell), MAX_RETRIES])


func _do_block_paint(hit: Dictionary) -> void:
	if _map_root == null or _block_vt == null or not hit.get("hit", false):
		return
	var cell := _target_cell(hit, false)
	if cell == Vector3i.MIN:
		return

	var bounds := _brush_box(cell)
	var ops: Array[Dictionary] = []
	for x in range(bounds[0].x, bounds[1].x + 1):
		for y in range(bounds[0].y, bounds[1].y + 1):
			for z in range(bounds[0].z, bounds[1].z + 1):
				var p := Vector3i(x, y, z)
				ops.append({"pos": p, "old_value": _block_vt.get_voxel(p)})
	_push_undo({"type": "block", "ops": ops})

	# Rotation-variant aware paint: resolve (base, rotation) to the renderable
	# stored index (plain base index for NONE blocks — identical to before).
	var stored: int = _selected_block_index
	if _block_library != null:
		stored = _block_library.get_stored_index(_selected_block_index, _active_rotation_index)
	_apply_block_brush(cell, stored)


func _do_block_erase(hit: Dictionary) -> void:
	if _map_root == null or _block_vt == null or not hit.get("hit", false):
		return
	var cell := _target_cell(hit, true)
	if cell == Vector3i.MIN:
		return

	var bounds := _brush_box(cell)
	var ops: Array[Dictionary] = []
	for x in range(bounds[0].x, bounds[1].x + 1):
		for y in range(bounds[0].y, bounds[1].y + 1):
			for z in range(bounds[0].z, bounds[1].z + 1):
				var p := Vector3i(x, y, z)
				ops.append({"pos": p, "old_value": _block_vt.get_voxel(p)})
	_push_undo({"type": "block", "ops": ops})

	_apply_block_brush(cell, 0)


func _do_terrain_add(hit: Dictionary) -> void:
	_sculpt(hit, true)


func _do_terrain_carve(hit: Dictionary) -> void:
	_sculpt(hit, false)


func _sculpt(hit: Dictionary, is_add: bool) -> void:
	## Auxiliary: Applies additive or subtractive smooth terrain sculpt with snapshot undo.
	if _map_root == null or _smooth_grid == null or not hit.get("hit", false):
		return
	var point: Vector3 = hit.get("point", Vector3.ZERO)
	# 1. Snapshot: Capture before edit so undo restores exact prior samples and material tags.
	_push_undo({"type": "terrain", "snapshot": _capture_brush_region(point, _sculpt_radius)})
	# 2. Edit: Modify smooth grid.
	if is_add:
		_smooth_grid.add_material(point, _terrain_material_id, _sculpt_radius)
	else:
		_smooth_grid.carve(point, _sculpt_radius)
	# 3. Persist: Flush modified smooth terrain blocks and mark dirty.
	_flush_terrains()
	_mark_dirty()


func _capture_brush_region(point: Vector3, radius: float) -> Dictionary:
	## Auxiliary: Captures SDF samples and block material metadata within sphere brush bounding box.
	if _smooth_grid == null:
		return {}
	var extent := Vector3.ONE * radius
	return _smooth_grid.capture_cells(SmoothGrid.region_cells(point - extent, point + extent))


func _do_furniture_place(hit: Dictionary) -> void:
	if _map_root == null or _furniture_auth == null or not hit.get("hit", false):
		return
	var cell := _target_cell(hit, false)
	if cell == Vector3i.MIN:
		return
	if _furniture_defs.is_empty() or _selected_furniture_idx < 0 or _selected_furniture_idx >= _furniture_defs.size():
		return
	var def := _furniture_defs[_selected_furniture_idx]
	if def == null:
		return
	var marker := _furniture_auth.place(def, cell, _yaw)
	if marker != null:
		_mark_dirty()


func _do_furniture_remove(hit: Dictionary) -> void:
	if _map_root == null or _furniture_auth == null or not hit.get("hit", false):
		return
	var cell := _target_cell(hit, false)
	var removed := false
	if cell != Vector3i.MIN:
		removed = _furniture_auth.remove_at(cell)
	if not removed:
		var solid_cell := _target_cell(hit, true)
		if solid_cell != Vector3i.MIN:
			removed = _furniture_auth.remove_at(solid_cell)
	if removed:
		_mark_dirty()


func _do_furniture_rotate_step(dir: int = 1) -> void:
	if dir > 0:
		_yaw = (_yaw + 1) % 4
	else:
		_yaw = (_yaw - 1 + 4) % 4
	_update_hud_info()
	if _camera != null and _ghost != null and _mode == Mode.FURNITURE:
		var hit := _raycast_from_camera()
		_update_ghost(hit)


func _cycle_furniture(dir: int) -> void:
	if _furniture_defs.is_empty():
		return
	# 1. Visible rows, or every def when the filter shows none (Tab still moves the selection).
	var visible: Array[int] = _hud.get_filtered_furniture_indices() if _hud != null else []
	var candidates := visible if not visible.is_empty() else _all_indices(_furniture_defs.size())
	# 2. Step with wrap, then mirror the selection into the HUD.
	_selected_furniture_idx = EditorPalettePanel.step_index(candidates, _selected_furniture_idx, dir)
	if _hud != null:
		_hud.select_furniture_by_index(_selected_furniture_idx)
	_update_hud_info()


func _all_indices(count: int) -> Array[int]:
	## Auxiliary: Generates an array of sequential integer indices.
	var out: Array[int] = []
	out.assign(range(count))
	return out


func _on_hud_furniture_selected(idx: int) -> void:
	if idx >= 0 and idx < _furniture_defs.size():
		_selected_furniture_idx = idx
		_update_hud_info()


func _on_water_apply_requested(enabled: bool, level: float) -> void:
	# 1. Unsaved Guard: Prompt for unsaved edits before applying water settings and reloading.
	_guard_unsaved(apply_water_settings.bind(level, enabled))


## Writes the water flags to MapDef and its map-owned terrain def, then reloads.
## WaterGenerator fills water only in blocks generated after the reload: blocks
## already stored in map.sqlite keep their contents (see docs/architecture/map-editor.md A6).
func apply_water_settings(level: float, enabled: bool = true) -> void:
	if _map_def == null:
		return
	# 1. Flags: Synchronize MapDef and terrain def water parameters.
	_apply_water_edits({"water_enabled": enabled, "water_level": level})
	# 2. Persistence: Commit modified terrain def and map definition to disk before reload.
	_persist_terrain_def()
	# 3. Persistence: Commit map configuration changes.
	_save_map_def()
	# 4. Reload: Rebuild scene and generator with updated water parameters.
	_reload_current_map()





func _do_spawn_place(type: String, hit: Dictionary) -> void:
	if _map_root == null or not hit.get("hit", false):
		return
	var spawn_points: Node3D = _map_root.find_child("SpawnPoints") as Node3D
	if spawn_points == null:
		spawn_points = Node3D.new()
		spawn_points.name = "SpawnPoints"
		_map_root.add_child(spawn_points)
		spawn_points.owner = _map_root

	var target_pos := _get_surface_hit_point(hit)

	if type == "player":
		var player_marker: Marker3D = _spawn_markers.get("player")
		if player_marker == null or not is_instance_valid(player_marker):
			player_marker = spawn_points.find_child(SpawnMarkerRules.PLAYER_NAME) as Marker3D
			if player_marker == null:
				player_marker = Marker3D.new()
				player_marker.name = SpawnMarkerRules.PLAYER_NAME
				spawn_points.add_child(player_marker)
				player_marker.owner = _map_root
			_spawn_markers["player"] = player_marker
		player_marker.global_position = target_pos
		_visualize_spawn(player_marker, Color(0.2, 1.0, 0.2, 0.5))
		if _map_def != null:
			_map_def.player_spawn = target_pos
	elif type == "colonist":
		# 1. Spawn Placement: Instantiate numbered colonist spawn marker.
		_place_numbered_spawn(spawn_points, SpawnMarkerRules.COLONIST_PREFIX, Color(0.2, 0.5, 1.0, 0.5), "colonists", target_pos)
	elif type == "enemy":
		# 1. Spawn Placement: Instantiate numbered enemy spawn marker.
		_place_numbered_spawn(spawn_points, SpawnMarkerRules.ENEMY_PREFIX, Color(1.0, 0.2, 0.2, 0.5), "enemies", target_pos)

	_update_spawn_hud_counts()
	_mark_dirty()


func _do_spawn_remove(hit: Dictionary) -> void:
	if _map_root == null or not hit.get("hit", false):
		return
	var spawn_points := _map_root.find_child("SpawnPoints") as Node3D
	if spawn_points == null:
		return
	# 1. Candidate: nearest real spawn marker; Furniture_* markers share the node but are never removable here.
	var marker := _nearest_spawn_marker(spawn_points, _get_surface_hit_point(hit), SPAWN_REMOVE_RANGE)
	if marker == null:
		return
	# 2. Bookkeeping: drop it from the cached lists (and MapDef for the player) before it is freed.
	_forget_spawn_marker(marker)
	marker.queue_free()
	_update_spawn_hud_counts()
	_mark_dirty()


func _nearest_spawn_marker(spawn_points: Node3D, target: Vector3, max_distance: float) -> Marker3D:
	## Auxiliary: Locates the nearest valid spawn marker within range.
	var best: Marker3D = null
	var best_dist := max_distance
	for child in spawn_points.get_children():
		if not (child is Marker3D) or SpawnMarkerRules.kind_of(child.name) == SpawnMarkerRules.Kind.NONE:
			continue
		var dist := (child as Marker3D).global_position.distance_to(target)
		if dist < best_dist:
			best_dist = dist
			best = child as Marker3D
	return best


func _forget_spawn_marker(marker: Marker3D) -> void:
	## Auxiliary: Removes a spawn marker from internal cache and map metadata.
	match SpawnMarkerRules.kind_of(marker.name):
		SpawnMarkerRules.Kind.PLAYER:
			_spawn_markers["player"] = null
			if _map_def != null:
				_map_def.player_spawn = Vector3.ZERO
		SpawnMarkerRules.Kind.COLONIST:
			(_spawn_markers["colonists"] as Array).erase(marker)
		SpawnMarkerRules.Kind.ENEMY:
			(_spawn_markers["enemies"] as Array).erase(marker)


func _place_numbered_spawn(spawn_points: Node3D, prefix: String, color: Color, list_key: String, world_pos: Vector3) -> void:
	## Auxiliary: Instantiates and tracks a numbered spawn marker with visualization.
	var names: Array[String] = []
	for child in spawn_points.get_children():
		names.append(String(child.name))
	var marker := Marker3D.new()
	marker.name = "%s_%d" % [prefix, SpawnMarkerRules.next_index(names, prefix)]
	spawn_points.add_child(marker)
	marker.owner = _map_root
	marker.global_position = world_pos
	_visualize_spawn(marker, color)
	(_spawn_markers[list_key] as Array).append(marker)


func _on_spawn_type_selected(type: String) -> void:
	_selected_spawn_type = type


func _cycle_spawn_type(dir: int) -> void:
	var types := ["player", "colonist", "enemy", "remove"]
	var idx := types.find(_selected_spawn_type)
	if idx == -1:
		idx = 0
	idx = posmod(idx + dir, types.size())
	_selected_spawn_type = types[idx]
	if _hud != null:
		_hud.set_spawn_type(_selected_spawn_type)


func _set_spawn_type_direct(type: String) -> void:
	_selected_spawn_type = type
	if _hud != null:
		_hud.set_spawn_type(_selected_spawn_type)


func _update_spawn_hud_counts() -> void:
	if _hud == null:
		return
	var player_set := _spawn_markers.get("player") != null and is_instance_valid(_spawn_markers["player"])
	var col_count := (_spawn_markers.get("colonists", []) as Array).size()
	var enemy_count := (_spawn_markers.get("enemies", []) as Array).size()
	_hud.set_spawn_counts(player_set, col_count, enemy_count)


func _do_structure_stamp(hit: Dictionary) -> void:
	if _map_root == null or _blocky_grid == null or not hit.get("hit", false):
		return
	if _structure_tool == null or _structure_tool.get_active_structure() == null:
		return
	var cell := _target_cell(hit, false)
	if cell == Vector3i.MIN:
		return

	var adapter := VoxelGridAdapter.new()
	adapter.set_grid(_blocky_grid)
	adapter.set_smooth_grid(_smooth_grid)

	# 1. Snapshot: terrain the stamp can touch before it writes anything, so undo restores it exactly.
	var terrain_snapshot := _capture_structure_terrain(cell)
	var ops := _structure_tool.stamp(adapter, cell)
	if ops.is_empty():
		push_warning("MapEditor: structure stamp wrote nothing at %s — check palette mapping" % str(cell))
		return
	_push_undo({"type": "structure", "ops": ops, "terrain_snapshot": terrain_snapshot})
	# 2. Persist: flush modified blocks to disk and mark dirty.
	_flush_terrains()
	_mark_dirty()


func _capture_structure_terrain(cell: Vector3i) -> Dictionary:
	## Auxiliary: Captures smooth terrain snapshot for cells touched by the structure stamp.
	if _smooth_grid == null:
		return {}
	var positions := _structure_tool.terrain_voxel_positions(cell)
	if positions.is_empty():
		return {}
	return _smooth_grid.capture_cells(SmoothGrid.cells_around(positions))


func _cache_spawn_markers() -> void:
	_spawn_markers = {
		"player": null,
		"colonists": [],
		"enemies": [],
	}
	if _map_root == null:
		return
	var spawns: Node3D = _map_root.find_child("SpawnPoints") as Node3D
	if spawns == null:
		return
	for child in spawns.get_children():
		if child is Marker3D:
			match SpawnMarkerRules.kind_of(child.name):
				SpawnMarkerRules.Kind.PLAYER:
					_spawn_markers["player"] = child
					_visualize_spawn(child, Color(0.2, 1.0, 0.2, 0.5))
				SpawnMarkerRules.Kind.COLONIST:
					(_spawn_markers["colonists"] as Array).append(child)
					_visualize_spawn(child, Color(0.2, 0.5, 1.0, 0.5))
				SpawnMarkerRules.Kind.ENEMY:
					(_spawn_markers["enemies"] as Array).append(child)
					_visualize_spawn(child, Color(1.0, 0.2, 0.2, 0.5))
	_update_spawn_hud_counts()


func _visualize_spawn(marker: Marker3D, color: Color) -> void:
	var existing := marker.get_node_or_null("SpawnVisualizer") as MeshInstance3D
	if existing != null:
		var mat := existing.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = color
		return
	var visualizer := MeshInstance3D.new()
	visualizer.name = "SpawnVisualizer"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	visualizer.mesh = capsule
	visualizer.position = Vector3(0, 0.9, 0)
	visualizer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visualizer.material_override = mat
	marker.add_child(visualizer)


func _cycle_block(dir: int) -> void:
	if _block_library == null:
		return
	# 1. Visible rows, or every base block when the filter shows none.
	var visible: Array[int] = _hud.get_filtered_block_indices() if _hud != null else []
	var candidates := visible if not visible.is_empty() else _block_library.get_base_indices()
	if candidates.is_empty():
		return
	# 2. Step with wrap, then keep the brush rotation valid for the new block.
	_selected_block_index = EditorPalettePanel.step_index(candidates, _selected_block_index, dir)
	# 3. Rotation Validation: Ensure active rotation index is valid for selected block definition.
	_sanitize_rotation_for_selected_block()
	if _hud != null:
		_hud.select_block_by_index(_selected_block_index)
	_update_hud_info()
	# 4. Ghost Refresh: Re-render ghost mesh for the newly selected block.
	_refresh_block_ghost()


func _on_hud_block_selected(idx: int) -> void:
	if _block_library != null and _block_library.get_def_by_index(idx) != null:
		_selected_block_index = idx
		# 1. Rotation Validation: Ensure active rotation index is valid for selected block definition.
		_sanitize_rotation_for_selected_block()
		_update_hud_info()
		# 2. Ghost Refresh: Re-render ghost mesh for the newly selected block.
		_refresh_block_ghost()


func _sanitize_rotation_for_selected_block() -> void:
	## Auxiliary: Clamps or resets rotation index depending on block rotatability.
	var def: BlockDef = _block_library.get_def_by_index(_selected_block_index)
	if def == null:
		return
	_active_rotation_index = def.sanitize_rotation(_active_rotation_index) if def.is_rotatable() else 0


func _refresh_block_ghost() -> void:
	## Auxiliary: Refreshes the active block placement ghost mesh under the cursor.
	if _camera != null and _ghost != null and _mode == Mode.BLOCK:
		_update_ghost(_raycast_from_camera())


## Terrain-mode material cycling — the mirror of BLOCK mode's block palette:
## M (Shift+M) cycles BuildLibrary's terrain materials into
## _terrain_material_id. Sculpted blobs carry the id persistently in the F12
## sidecar (per-block metadata dict); visually the terrain stays one look per
## map (F8/F11) — the id is dig-action stats (hp/yields), not a paint job.
func _cycle_terrain_material(dir: int) -> void:
	var mats: Array = BuildLibrary.get_terrain_materials()
	if mats.is_empty():
		return
	var ids: Array[String] = []
	for m in mats:
		var mat := m as TerrainMaterialDef
		if mat != null and not mat.id.is_empty():
			ids.append(mat.id)
	if ids.is_empty():
		return
	var idx: int = ids.find(_terrain_material_id)
	if idx < 0:
		_terrain_material_id = ids[0]
	else:
		_terrain_material_id = ids[(idx + dir + ids.size()) % ids.size()]
	_update_hud_info()


## HUD label for the active terrain material: "Display Name (i/N)" so cycling
## gives position feedback like the block palette's "[#idx]" labels.
func _terrain_material_display() -> String:
	var mats: Array = BuildLibrary.get_terrain_materials()
	for i in mats.size():
		var mat := mats[i] as TerrainMaterialDef
		if mat != null and mat.id == _terrain_material_id:
			var name: String = mat.display_name if not mat.display_name.is_empty() else mat.id
			return "%s (%d/%d)" % [name, i + 1, mats.size()]
	return _terrain_material_id


func _update_hud_info() -> void:
	if _hud == null:
		return
	var axis_name := _get_rotation_axis_name()
	if _block_library != null:
		var def: BlockDef = _block_library.get_def_by_index(_selected_block_index)
		var block_name := def.display_name if def != null and not def.display_name.is_empty() else (def.id if def != null else "Unknown")
		var block_id := def.id if def != null else ""
		_hud.set_block_info(block_name, _brush_diameter, block_id, _selected_block_index, _active_rotation_index, axis_name)
	_hud.set_terrain_info(_terrain_material_display(), _sculpt_radius)
	if not _furniture_defs.is_empty() and _selected_furniture_idx >= 0 and _selected_furniture_idx < _furniture_defs.size():
		var fdef: FurnitureDef = _furniture_defs[_selected_furniture_idx]
		var fname := fdef.display_name if fdef != null and not fdef.display_name.is_empty() else (fdef.id if fdef != null else "Unknown")
		var dims := fdef.dimensions if fdef != null else Vector3i.ONE
		var fid := fdef.id if fdef != null else ""
		_hud.set_furniture_info(fname, _yaw, dims, fid, axis_name)
	else:
		_hud.set_furniture_info("None", _yaw, Vector3i.ONE, "", axis_name)


func save_map() -> bool:
	if _map_root == null or _map_def == null:
		return false
	# 1. Streams: persist uncommitted voxel blocks to sqlite first so the scene never outruns its terrain.
	_map_root.flush_voxel_streams()
	# 2. Spawns: player and enemy marker positions into MapDef, the runtime source of truth.
	_sync_spawns_into_def()
	# 3. Metadata: only fields the author changed, so spinner rounding cannot rewrite untouched values.
	_apply_metadata_edits()
	# 4. Persist both files; dirty clears only when both succeeded.
	var saved := _save_map_def() and _persist_map_scene()
	if saved:
		_dirty = false
	# 5. Map Info: Refreshing HUD to show clean or dirty status after save attempt.
	_refresh_map_info()
	return saved


func _sync_spawns_into_def() -> void:
	## Auxiliary: Syncs player and enemy spawn markers to MapDef properties.
	var player: Variant = _spawn_markers.get("player")
	if player != null and is_instance_valid(player):
		_map_def.player_spawn = (player as Marker3D).global_position
	var enemies: Array[Dictionary] = []
	for marker: Variant in _spawn_markers.get("enemies", []):
		if marker != null and is_instance_valid(marker):
			enemies.append({"pos": (marker as Marker3D).global_position, "count": 1})
	_map_def.enemy_spawns = enemies


func _apply_metadata_edits() -> void:
	## Auxiliary: Updates MapDef properties from modified fields in HUD metadata panel.
	if _hud == null:
		return
	var edits: Dictionary = _hud.get_metadata_edits()
	# 1. Plain fields share their name with the MapDef property.
	for key: String in METADATA_KEYS:
		if edits.has(key):
			_map_def.set(key, edits[key])
	# 2. Bounds also resize the live map, so they are applied separately.
	_apply_world_bounds_edit(edits)


func _apply_world_bounds_edit(edits: Dictionary) -> void:
	## Auxiliary: Applies world_bounds edit to MapDef and live map.
	if not (edits.get("world_bounds") is AABB):
		return
	_map_def.world_bounds = edits["world_bounds"]
	_map_root.set_world_bounds(_map_def.world_bounds)


func _save_map_def() -> bool:
	## Auxiliary: Saves MapDef resource to disk.
	if _map_def == null:
		return false
	var def_path := MAPS_DIR + _map_def.id + "/map_def.tres"
	var err := ResourceSaver.save(_map_def, def_path)
	if err != OK:
		push_warning("MapEditor: failed to save MapDef to '%s' (error %d)" % [def_path, err])
	return err == OK


func _persist_map_scene() -> bool:
	## Auxiliary: Packs and saves map scene to disk.
	if _map_scene_path.is_empty():
		return true
	# 1. Pack: strip injected terrain def before packing so SceneManager does not resurrect deleted terrain at runtime.
	var packed := _pack_map_scene()
	if packed == null:
		return false
	var err := ResourceSaver.save(packed, _map_scene_path)
	if err != OK:
		push_warning("MapEditor: failed to save scene to '%s' (error %d)" % [_map_scene_path, err])
	return err == OK



## Packs the live map without the injected terrain def. Runtime SceneManager only
## injects a def when MapDef.terrain_gen is non-null, so an embedded copy would
## resurrect terrain the author removed.
func _pack_map_scene() -> PackedScene:
	var smooth := _map_root.get_smooth_grid()
	var live_def: TerrainGenDef = null
	if smooth != null and is_instance_valid(smooth):
		live_def = smooth.terrain_gen
		smooth.terrain_gen = null
	var packed := PackedScene.new()
	var err := packed.pack(_map_root)
	if smooth != null and is_instance_valid(smooth):
		smooth.terrain_gen = live_def
	if err != OK:
		push_warning("MapEditor: failed to pack map scene (error %d)" % err)
		return null
	return packed


func _get_rotation_axis_vector() -> Vector3:
	match _active_rotation_axis:
		RotationAxis.X: return Vector3.RIGHT
		RotationAxis.Y: return Vector3.UP
		RotationAxis.Z: return Vector3.FORWARD
		_: return Vector3.UP


func _get_rotation_axis_name() -> String:
	match _active_rotation_axis:
		RotationAxis.X: return "X [Pitch]"
		RotationAxis.Y: return "Y [Yaw]"
		RotationAxis.Z: return "Z [Roll]"
		_: return "Y [Yaw]"


func _cycle_rotation_axis() -> void:
	_active_rotation_axis = (_active_rotation_axis + 1) % 3
	_update_hud_info()
	if _camera != null and _ghost != null and (_mode == Mode.BLOCK or _mode == Mode.FURNITURE):
		var hit := _raycast_from_camera()
		_update_ghost(hit)


func _update_axis_line(pos: Vector3) -> void:
	if _axis_line == null or _axis_line_mat == null:
		return
	_axis_line.global_position = pos
	match _active_rotation_axis:
		RotationAxis.Y:
			_axis_line.transform.basis = Basis.IDENTITY
			_axis_line_mat.albedo_color = Color(0.2, 1.0, 0.2, 0.95)
		RotationAxis.X:
			_axis_line.transform.basis = Basis(Vector3.FORWARD, deg_to_rad(90))
			_axis_line_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.95)
		RotationAxis.Z:
			_axis_line.transform.basis = Basis(Vector3.RIGHT, deg_to_rad(90))
			_axis_line_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.95)
	_axis_line.visible = true


func _hide_axis_line() -> void:
	if _axis_line != null:
		_axis_line.visible = false


func _rotate_block_brush(axis: Vector3, step_angle_rad: float = PI / 2.0) -> void:
	_active_rotation_index = VoxelBlockEncoder.rotate_around_axis(_active_rotation_index, axis, step_angle_rad)
	if _block_library != null:
		var def: BlockDef = _block_library.get_def_by_index(_selected_block_index)
		if def != null and def.is_rotatable():
			_active_rotation_index = def.sanitize_rotation(_active_rotation_index)
	_update_hud_info()
	var hit := _raycast_from_camera()
	_update_ghost(hit)


func _reset_block_rotation() -> void:
	_active_rotation_index = 0
	_active_rotation_axis = RotationAxis.Y
	_yaw = 0
	_update_hud_info()
	var hit := _raycast_from_camera()
	_update_ghost(hit)


func _do_block_pick(hit: Dictionary) -> void:
	if _map_root == null or _blocky_grid == null or not hit.get("hit", false):
		return
	var hovered_pos: Vector3i = hit.get("position", Vector3i.ZERO)
	var raw: int = _blocky_grid.get_raw_voxel(hovered_pos)
	if raw <= 0:
		return
	# The stored value may be a rotation-variant index; the palette selection
	# and rotation state want the def's base index + the orientation.
	_selected_block_index = _blocky_grid.get_block_type(hovered_pos)
	_active_rotation_index = _blocky_grid.get_block_rotation(hovered_pos)
	if _hud != null:
		_hud.select_block_by_index(_selected_block_index)
	_update_hud_info()
	_update_ghost(hit)


func _cycle_structure(dir: int) -> void:
	if _structure_defs.is_empty():
		return
	var visible: Array[int] = _hud.get_filtered_structure_indices() if _hud != null else []
	var candidates := visible if not visible.is_empty() else _all_indices(_structure_defs.size())
	_selected_structure_idx = EditorPalettePanel.step_index(candidates, _selected_structure_idx, dir)
	if _structure_tool != null and _selected_structure_idx >= 0 and _selected_structure_idx < _structure_defs.size():
		_structure_tool.set_active_structure(_structure_defs[_selected_structure_idx])
	if _hud != null:
		_hud.select_structure_by_index(_selected_structure_idx)
		_update_structure_info()


func _on_hud_structure_selected(idx: int) -> void:
	if idx >= 0 and idx < _structure_defs.size():
		_selected_structure_idx = idx
		if _structure_tool != null:
			_structure_tool.set_active_structure(_structure_defs[idx])
		_update_structure_info()


func _update_structure_info() -> void:
	if _hud == null:
		return
	if not _structure_defs.is_empty() and _selected_structure_idx >= 0 and _selected_structure_idx < _structure_defs.size():
		var sdef: StructureDef = _structure_defs[_selected_structure_idx]
		_hud.set_structure_info(sdef)
	else:
		_hud.set_structure_info(null)
