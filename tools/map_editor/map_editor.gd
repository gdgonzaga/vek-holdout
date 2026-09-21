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
const EditorUndoHistoryClass = preload("res://tools/map_editor/editor_undo_history.gd")

const CONFIG_PATH: String = "res://data/map_editor/map_editor_config.tres"

const FLY_SPEED: float = 8.0
const FLY_SPEED_FAST: float = 20.0
const MOUSE_SENSITIVITY: float = 0.2

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
var _config: MapEditorConfig = null
var _dirty: bool = false
var _history: EditorUndoHistory = EditorUndoHistory.new()

var _blocky_grid: BlockyGrid = null
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
var _sculpt_radius: float = 2.0
var _terrain_material_id: String = ""

var _furniture_auth: FurnitureAuthoring = null
var _furniture_defs: Array[FurnitureDef] = []
var _selected_furniture_idx: int = 0
var _structure_defs: Array[StructureDef] = []
var _selected_structure_idx: int = 0
var _structure_tool: StructureToolClass = null
var _yaw: int = 0 # Quarter turns (0..3)
var _spawns: SpawnAuthoring = SpawnAuthoring.new()
var _selected_spawn_type: String = "player"

var _ghost_view: EditorGhost = null

var _cam_yaw: float = 0.0
var _cam_pitch: float = -30.0


func _ready() -> void:
	# 1. Configuration: load editor config resource.
	_load_config()
	# 2. Scene: initialize environment, camera, and authoring tools.
	_build_environment()
	_build_camera()
	_init_tools()
	# 3. HUD: instantiate HUD and connect all event signals.
	_setup_hud()
	# 4. Launcher: instantiate launcher and wire map selection signals.
	_setup_launcher()
	# 5. Dialogs: create confirmation modal dialogs.
	_setup_exit_dialog()
	_setup_delete_dialog()
	_setup_unsaved_dialog()


func _load_config() -> void:
	## Auxiliary: Loads the MapEditorConfig resource.
	_config = load(CONFIG_PATH) as MapEditorConfig
	if _config == null:
		push_error("MapEditor: failed to load config at %s" % CONFIG_PATH)


func _init_tools() -> void:
	## Auxiliary: Instantiates authoring tools, content loaders, and libraries.
	_ghost_view = EditorGhost.new()
	_ghost_view.name = "EditorGhost"
	add_child(_ghost_view)
	_ghost_view.setup()
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


func _setup_hud() -> void:
	## Auxiliary: Creates EditorHUD instance and connects editor action signals.
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


func _setup_launcher() -> void:
	## Auxiliary: Creates EditorLauncher instance, connects requests, and seeds lists.
	_launcher = EditorLauncherClass.new()
	add_child(_launcher)
	_launcher.map_selected.connect(load_map)
	_launcher.new_map_requested.connect(func(payload: Dictionary) -> void:
		create_new_map(payload)
	)
	_launcher.map_delete_requested.connect(_request_delete_map)
	_launcher.setup(MapRepository.scan_maps())
	var default_noise_path := ""
	if _config != null and _config.default_noise_def != null:
		default_noise_path = _config.default_noise_def.resource_path
	_launcher.setup_noise_defs(MapRepository.scan_noise_defs(), default_noise_path)
	_launcher.show_launcher()


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


func _undo_last() -> void:
	if _history.is_empty() or _map_root == null:
		return
	var entry: Dictionary = _history.pop()
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
	if (_launcher != null and _launcher.visible) or _modal_dialog_open():
		return
	# 1. Text focus: route keyboard events to text input handler when HUD controls are focused.
	if _hud != null and _hud.is_any_input_focused():
		_handle_text_focus_input(event)
		return
	if event is InputEventMouseButton:
		# 2. Mouse button: route clicks and scrolling to mouse button handler.
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		# 3. Keyboard shortcut: route key press to shortcut handler.
		_handle_key(event as InputEventKey)
	elif event is InputEventMouseMotion:
		# 4. Mouse motion: update free-cam orientation when captured.
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_text_focus_input(event: InputEvent) -> void:
	## Auxiliary: Handles keyboard events when text controls (e.g. search / metadata) have focus.
	if not (event is InputEventKey and (event as InputEventKey).pressed):
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_ENTER:
		_hud.unfocus_search()
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_TAB and _hud.is_search_focused():
		var dir := -1 if key_event.shift_pressed else 1
		# 1. Cycle selection: cycle active content within focused search.
		_cycle_focused_mode_content(dir)
		get_viewport().set_input_as_handled()


func _cycle_focused_mode_content(dir: int) -> void:
	## Auxiliary: Cycles active item in HUD-focused search for current mode.
	match _mode:
		Mode.BLOCK:
			_cycle_block(dir)
		Mode.FURNITURE:
			_cycle_furniture(dir)
		Mode.SPAWN:
			_cycle_spawn_type(dir)
		Mode.STRUCTURE:
			_cycle_structure(dir)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	## Auxiliary: Routes mouse button events to picking, capture, painting, or wheel scrolling.
	if not mb.pressed:
		return
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
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# 1. Action dispatch: Perform primary tool action for the active mode.
			_handle_lmb(mb)
			get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		# 1. Viewport Routing: Allow hovered GUI controls to scroll when cursor is uncaptured.
		if not _wheel_reaches_viewport():
			return
		# 2. Wheel dispatch: Process tool size, rotation, or structure offset adjustments.
		_handle_wheel(mb)
		get_viewport().set_input_as_handled()


func _handle_lmb(mb: InputEventMouseButton) -> void:
	## Auxiliary: Dispatches left mouse click to mode-specific paint/erase/stamp handlers.
	match _mode:
		Mode.BLOCK:
			var hit := _raycast_from_camera()
			if mb.shift_pressed:
				_do_block_erase(hit)
			else:
				_do_block_paint(hit)
		Mode.TERRAIN:
			var hit := _raycast_terrain()
			if mb.shift_pressed:
				_do_terrain_carve(hit)
			else:
				_do_terrain_add(hit)
		Mode.FURNITURE:
			var hit := _raycast_from_camera()
			if mb.shift_pressed:
				_do_furniture_remove(hit)
			else:
				_do_furniture_place(hit)
		Mode.SPAWN:
			var hit := _raycast_from_camera()
			if mb.shift_pressed or _selected_spawn_type == "remove":
				_do_spawn_remove(hit)
			else:
				_do_spawn_place(_selected_spawn_type, hit)
		Mode.STRUCTURE:
			var hit := _raycast_from_camera()
			_do_structure_stamp(hit)


func _handle_wheel(mb: InputEventMouseButton) -> void:
	## Auxiliary: Adjusts brush diameter, sculpt radius, or rotation using mouse wheel.
	var wheel_dir := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
	if Input.is_key_pressed(KEY_B):
		if _mode == Mode.BLOCK:
			_brush_diameter = clampi(_brush_diameter + wheel_dir, 1, MAX_BRUSH_DIAMETER)
		elif _mode == Mode.TERRAIN:
			_sculpt_radius = clampf(_sculpt_radius + float(wheel_dir) * 0.5, MIN_SCULPT_RADIUS, MAX_SCULPT_RADIUS)
		_update_hud_info()
	elif _mode == Mode.BLOCK:
		_rotate_block_brush(_get_rotation_axis_vector(), (PI / 2.0) * float(wheel_dir))
	elif _mode == Mode.FURNITURE:
		_do_furniture_rotate_step(wheel_dir)
	elif _mode == Mode.STRUCTURE:
		# 1. Structure wheel adjustment: adjust Y offset or rotate structure.
		_handle_structure_wheel(wheel_dir, mb.ctrl_pressed, mb.shift_pressed)


func _handle_structure_wheel(wheel_dir: int, ctrl_pressed: bool, shift_pressed: bool) -> void:
	## Auxiliary: Handles mouse wheel scrolling in STRUCTURE mode for Y offset and rotation.
	if _structure_tool == null:
		return
	if ctrl_pressed:
		var step := 5 if shift_pressed else 1
		_structure_tool.adjust_y_offset(wheel_dir * step)
	else:
		if wheel_dir > 0:
			_structure_tool.rotate_clockwise()
		else:
			_structure_tool.rotate_counter_clockwise()
	_update_structure_info()


func _handle_key(k: InputEventKey) -> void:
	## Auxiliary: Dispatches keyboard shortcuts to specialized action helpers.
	match k.keycode:
		KEY_ESCAPE:
			# 1. Escape: close active sub-panels, drop mouse capture, or request map exit.
			_handle_escape()
		KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6:
			# 1. Mode switch: switch active authoring mode.
			_handle_mode_key(k.keycode)
		KEY_1, KEY_2, KEY_3, KEY_4:
			if _mode == Mode.SPAWN:
				# 1. Spawn selection: select specific spawn marker type.
				_handle_spawn_numeric_key(k.keycode)
		KEY_G:
			_toggle_grid()
			get_viewport().set_input_as_handled()
		KEY_Z:
			if k.ctrl_pressed:
				_undo_last()
				get_viewport().set_input_as_handled()
			elif _mode == Mode.BLOCK:
				_reset_block_rotation()
				get_viewport().set_input_as_handled()
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			# 1. Bracket step: adjust brush size, sculpt radius, or palette selection.
			_handle_bracket_key(k.keycode)
		KEY_TAB:
			# 1. Tab cycling: cycle active block, furniture, spawn type, or structure.
			_handle_tab_key(k.shift_pressed)
		KEY_R:
			# 1. Rotation key: cycle rotation axis or rotate selected structure.
			_handle_rotate_key()
		KEY_QUOTELEFT, KEY_SECTION, KEY_ASCIITILDE:
			if _mode == Mode.BLOCK:
				_reset_block_rotation()
				get_viewport().set_input_as_handled()
		KEY_I:
			if _mode == Mode.BLOCK:
				var hit := _raycast_from_camera()
				_do_block_pick(hit)
				get_viewport().set_input_as_handled()
		KEY_M:
			if _mode == Mode.TERRAIN:
				_cycle_terrain_material(-1 if k.shift_pressed else 1)
				get_viewport().set_input_as_handled()
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			if _mode == Mode.STRUCTURE:
				# 1. Structure nudge: adjust X/Z grid offset.
				_handle_structure_arrow_key(k.keycode, k.shift_pressed)
		KEY_S:
			if k.ctrl_pressed:
				save_map()
				get_viewport().set_input_as_handled()


func _handle_escape() -> void:
	## Auxiliary: Handles Escape key to dismiss drawer, uncapture mouse, or request exit.
	if _hud != null and _hud.is_terrain_drawer_visible():
		_hud.close_terrain_drawer()
		get_viewport().set_input_as_handled()
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_request_exit()


func _handle_mode_key(keycode: int) -> void:
	## Auxiliary: Switches active editor mode based on F1-F6 function keys.
	match keycode:
		KEY_F1: _set_mode(Mode.NAVIGATE)
		KEY_F2: _set_mode(Mode.BLOCK)
		KEY_F3: _set_mode(Mode.TERRAIN)
		KEY_F4: _set_mode(Mode.FURNITURE)
		KEY_F5: _set_mode(Mode.SPAWN)
		KEY_F6: _set_mode(Mode.STRUCTURE)


func _handle_spawn_numeric_key(keycode: int) -> void:
	## Auxiliary: Sets spawn authoring type directly using 1-4 number keys.
	match keycode:
		KEY_1: _set_spawn_type_direct("player")
		KEY_2: _set_spawn_type_direct("colonist")
		KEY_3: _set_spawn_type_direct("enemy")
		KEY_4: _set_spawn_type_direct("remove")
	get_viewport().set_input_as_handled()


func _handle_bracket_key(keycode: int) -> void:
	## Auxiliary: Steps palette selection or sculpt radius up or down with brackets.
	var step := -1 if keycode == KEY_BRACKETLEFT else 1
	match _mode:
		Mode.BLOCK:
			_cycle_block(step)
		Mode.TERRAIN:
			_sculpt_radius = clampf(_sculpt_radius + float(step) * 0.5, MIN_SCULPT_RADIUS, MAX_SCULPT_RADIUS)
			_update_hud_info()
		Mode.FURNITURE:
			_cycle_furniture(step)
		Mode.STRUCTURE:
			_cycle_structure(step)


func _handle_tab_key(shift_pressed: bool) -> void:
	## Auxiliary: Cycles active content forwards or backwards in the current mode.
	var dir := -1 if shift_pressed else 1
	match _mode:
		Mode.BLOCK:
			_cycle_block(dir)
		Mode.FURNITURE:
			_cycle_furniture(dir)
		Mode.SPAWN:
			_cycle_spawn_type(dir)
		Mode.STRUCTURE:
			_cycle_structure(dir)
	get_viewport().set_input_as_handled()


func _handle_rotate_key() -> void:
	## Auxiliary: Cycles rotation axis in BLOCK/FURNITURE mode, or rotates in STRUCTURE mode.
	if _mode == Mode.BLOCK or _mode == Mode.FURNITURE:
		_cycle_rotation_axis()
		get_viewport().set_input_as_handled()
	elif _mode == Mode.STRUCTURE:
		if _structure_tool != null:
			_structure_tool.rotate_clockwise()
			_update_structure_info()
		get_viewport().set_input_as_handled()


func _handle_structure_arrow_key(keycode: int, shift_pressed: bool) -> void:
	## Auxiliary: Nudges the active structure preview along X or Z axis.
	var step := 5 if shift_pressed else 1
	var offset := Vector3i.ZERO
	match keycode:
		KEY_UP: offset.z -= step
		KEY_DOWN: offset.z += step
		KEY_LEFT: offset.x -= step
		KEY_RIGHT: offset.x += step
	if _structure_tool != null:
		_structure_tool.nudge(offset)
		_update_structure_info()
	get_viewport().set_input_as_handled()


func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	## Auxiliary: Updates camera pitch and yaw when cursor is captured.
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
		# 1. Feedback Cleanup: Hide ghost visual and clear coordinate HUD readout when inactive.
		_hide_hover_feedback()
		return
	# 2. Hover: perform raycast for active mode, then update ghost and coordinate readout.
	var hit := _raycast_terrain() if _mode == Mode.TERRAIN else _raycast_from_camera()
	_update_ghost(hit)
	_show_hit_coordinates(hit)
	# 3. Fly camera: update camera position based on keyboard navigation input.
	_fly_camera(delta)


func _hide_hover_feedback() -> void:
	## Auxiliary: Hides ghost preview and clears coordinate readout when hovering is inactive.
	if _ghost_view != null:
		_ghost_view.hide_all()
	if _hud != null:
		_hud.clear_coordinates()


func _show_hit_coordinates(hit: Dictionary) -> void:
	## Auxiliary: Updates HUD coordinate display from raycast hit position.
	if _hud == null:
		return
	if hit.get("hit", false):
		var point: Vector3 = hit.get("point", Vector3.ZERO) if _mode == Mode.TERRAIN else _get_surface_hit_point(hit)
		_hud.set_coordinates(point)
	else:
		_hud.clear_coordinates()


func _fly_camera(delta: float) -> void:
	## Auxiliary: Calculates free-cam velocity and updates camera position.
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
	# 1. Map definition: load and validate MapDef resource from disk.
	var def := _read_map_def(map_id)
	if def == null:
		return

	# 2. Scene instantiation: instantiate map scene and apply bounds.
	var instance := _instantiate_map(def)
	if instance == null:
		return

	_map_root = instance
	_map_def = def
	_map_scene_path = def.scene_path
	_dirty = false
	_history.clear()

	# 3. State binding: wire voxel grids, streams, authoring tools, and camera.
	_bind_map_state(map_id)

	# 4. HUD initialization: populate palettes, metadata, and drawers.
	_populate_hud_for_map(def)

	if _launcher != null:
		_launcher.hide_launcher()

	if recapture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _read_map_def(map_id: String) -> MapDef:
	## Auxiliary: Loads the MapDef resource from disk for the specified map identifier.
	var def_path := MapRepository.MAPS_DIR + map_id + "/map_def.tres"
	if not ResourceLoader.exists(def_path):
		push_error("MapEditor: map_def not found at '%s'" % def_path)
		return null

	var def: MapDef = load(def_path) as MapDef
	if def == null:
		push_error("MapEditor: failed to load MapDef from '%s'" % def_path)
		return null
	return def


func _instantiate_map(def: MapDef) -> Map:
	## Auxiliary: Frees previous map root, instantiates the scene, injects terrain gen, and adds to tree.
	if _map_root != null:
		_map_root.queue_free()
		_map_root = null

	if not ResourceLoader.exists(def.scene_path):
		push_error("MapEditor: scene not found at '%s'" % def.scene_path)
		return null

	var packed: PackedScene = load(def.scene_path) as PackedScene
	if packed == null:
		push_error("MapEditor: failed to load PackedScene '%s'" % def.scene_path)
		return null

	var instance := packed.instantiate()
	_inject_terrain_gen(instance, def)
	if instance is Map and def != null:
		(instance as Map).set_world_bounds(def.world_bounds)
	add_child(instance)
	return instance as Map


func _bind_map_state(map_id: String) -> void:
	## Auxiliary: Binds grids, terrain material, streams, furniture, spawn markers, and camera position.
	_blocky_grid = _map_root.blocky_grid

	# 1. Smooth Grid: Resolving active live smooth grid to confirm valid terrain generator exists.
	_smooth_grid = _resolve_live_smooth_grid()
	if _smooth_grid != null:
		if _smooth_grid.default_material != null and not _smooth_grid.default_material.id.is_empty():
			_terrain_material_id = _smooth_grid.default_material.id
		else:
			# Empty material id defaults to the terrain's base material behavior without hardcoding content IDs.
			_terrain_material_id = ""
	else:
		_terrain_material_id = ""

	_attach_streams(_map_root, map_id)
	if _furniture_auth != null:
		_furniture_auth.bind(_map_root)
	_spawns.bind(_map_root)
	_position_camera_at_spawn()


func _populate_hud_for_map(def: MapDef) -> void:
	## Auxiliary: Initializes all HUD panels, palettes, metadata, and drawer states for the loaded map.
	if _hud == null:
		return
	_hud.populate_block_library(_block_library, _selected_block_index)
	_hud.populate_furniture_list(_furniture_defs, _selected_furniture_idx)
	_hud.populate_structure_list(_structure_defs, _selected_structure_idx)
	_hud.set_map_info(def.id, _dirty)
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
	# 1. Files: validation, folder, scene stamp, MapDef and terrain def (all disk work, no editor state).
	var scene_path := MapRepository.create_map_files(payload, _config)
	if scene_path.is_empty():
		return ""
	# 2. UI: refresh the launcher list, then open the new map.
	if _launcher != null:
		_launcher.setup(MapRepository.scan_maps())
	load_map(payload["map_id"])
	return scene_path


func unload_map() -> void:
	# 1. Dialogs: Dismiss any visible confirmation dialogs.
	_dismiss_dialogs()
	if _dirty:
		push_warning("MapEditor: unloading with unsaved changes")
	# 2. Authoring tools: Unbind authoring components and hide ghost previews.
	_unbind_authoring_tools()
	# 3. Scene cleanup: Free loaded map instance and clear editor state references.
	_clear_loaded_map_state()
	# 4. Viewport: Restore launcher view and reset mouse capture.
	_restore_launcher_view()


func _dismiss_dialogs() -> void:
	## Auxiliary: Hides confirmation dialogs if currently visible.
	for dialog: ConfirmationDialog in [_exit_dialog, _delete_dialog, _unsaved_dialog]:
		if dialog != null and dialog.visible:
			dialog.hide()


func _unbind_authoring_tools() -> void:
	## Auxiliary: Unbinds furniture authoring, spawns, and structure preview tools.
	if _furniture_auth != null:
		_furniture_auth.unbind()
	if _structure_tool != null:
		_structure_tool.hide_ghost()
	_spawns.unbind()


func _clear_loaded_map_state() -> void:
	## Auxiliary: Frees the map instance node and resets active map state properties.
	if _map_root != null:
		_map_root.queue_free()
		_map_root = null
	_map_def = null
	_map_scene_path = ""
	_dirty = false
	_history.clear()
	_blocky_grid = null
	_smooth_grid = null


func _restore_launcher_view() -> void:
	## Auxiliary: Hides editor HUD, displays the launcher dialog, and releases mouse capture.
	if _hud != null:
		_hud.hide()
	if _launcher != null:
		_launcher.setup(MapRepository.scan_maps())
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
	MapRepository.delete_map(map_id)
	if _launcher != null:
		_launcher.setup(MapRepository.scan_maps())


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


func _position_camera_at_spawn() -> void:
	if _map_def != null:
		_camera.global_position = _map_def.player_spawn + Vector3(0.0, 2.0, 5.0)
	else:
		_camera.global_position = Vector3(0.0, 10.0, 20.0)
	_cam_yaw = 0.0
	_cam_pitch = -20.0
	_apply_camera_rotation()





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
	MapTerrainAuthoring.persist_owned(_map_def.terrain_gen, MapRepository.MAPS_DIR, _map_def.id)


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
	var map_dir := MapRepository.MAPS_DIR + map_id + "/"
	# 1. Blocky stream: bind map.sqlite to blocky voxel terrain.
	_attach_terrain_stream(_resolve_blocky_terrain(map), map_dir + "map.sqlite")
	# 2. Smooth stream: bind terrain.sqlite to smooth voxel terrain.
	_attach_terrain_stream(_resolve_smooth_terrain(map), map_dir + "terrain.sqlite")


func _resolve_blocky_terrain(map: Node) -> VoxelTerrain:
	## Auxiliary: Resolves the active blocky VoxelTerrain node from the map.
	if map is Map and (map as Map).get_blocky_terrain() != null:
		return (map as Map).get_blocky_terrain()
	if map != null:
		return map.get_node_or_null("BlockyGrid/VoxelTerrain") as VoxelTerrain
	return null


func _resolve_smooth_terrain(map: Node) -> VoxelTerrain:
	## Auxiliary: Resolves the active smooth VoxelTerrain node from the map.
	if map is Map and (map as Map).get_smooth_terrain() != null:
		return (map as Map).get_smooth_terrain()
	if map != null:
		return map.get_node_or_null("SmoothGrid/VoxelTerrain") as VoxelTerrain
	return null


func _attach_terrain_stream(terrain: VoxelTerrain, stream_path: String) -> void:
	## Auxiliary: Configures or creates a VoxelStreamSQLite instance pointing to stream_path.
	if terrain == null:
		return
	if terrain.stream is VoxelStreamSQLite:
		(terrain.stream as VoxelStreamSQLite).database_path = stream_path
	elif terrain.stream == null:
		var stream := VoxelStreamSQLite.new()
		stream.database_path = stream_path
		terrain.stream = stream


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

	if _ghost_view != null:
		_ghost_view.hide_all()


func _update_ghost(hit: Dictionary) -> void:
	if _ghost_view == null:
		return

	match _mode:
		Mode.BLOCK:
			# 1. Block Ghost: Preview block brush footprint or single-voxel custom mesh.
			_ghost_block(hit)
		Mode.TERRAIN:
			# 1. Terrain Ghost: Preview sculpting sphere at hit point.
			_ghost_terrain(hit)
		Mode.FURNITURE:
			# 1. Furniture Ghost: Preview furniture item mesh and yaw orientation.
			_ghost_furniture(hit)
		Mode.SPAWN:
			# 1. Spawn Ghost: Preview spawn marker capsule.
			_ghost_spawn(hit)
		Mode.STRUCTURE:
			# 1. Structure Ghost: Update structure stamp ghost via structure tool.
			_ghost_structure(hit)
		_:
			# 1. Hide Ghost: Conceal ghost preview and rotation axis line.
			_ghost_view.hide_all()


func _ghost_block(hit: Dictionary) -> void:
	## Auxiliary: Updates block brush ghost mesh and rotation axis line.
	var is_erase: bool = Input.is_key_pressed(KEY_SHIFT)
	if not hit.get("hit", false):
		_ghost_view.hide_all()
		return
	var cell: Vector3i = _target_cell(hit, is_erase)
	if cell == Vector3i.MIN:
		_ghost_view.hide_all()
		return
	var cell_center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var rot_basis := VoxelBlockEncoder.rot_index_to_basis(_active_rotation_index)
	var def: BlockDef = _block_library.get_def_by_index(_selected_block_index) if _block_library != null else null
	var eff_mesh: Mesh = def.get_mesh() if def != null else null
	if not is_erase and def != null and eff_mesh != null and _brush_diameter == 1:
		var mesh_aabb := eff_mesh.get_aabb()
		var local_center := mesh_aabb.get_center()
		_ghost_view.show_custom_mesh(eff_mesh, cell_center - rot_basis * local_center, rot_basis, is_erase)
	else:
		var bounds := _brush_box(cell)
		var center := _box_center(bounds)
		var scaled_basis := rot_basis.scaled(Vector3(_brush_diameter, _brush_diameter, _brush_diameter))
		_ghost_view.show_box(center, scaled_basis, is_erase)
	if not is_erase:
		_ghost_view.show_axis(cell_center, _active_rotation_axis)
	else:
		_ghost_view.hide_axis()


func _ghost_terrain(hit: Dictionary) -> void:
	## Auxiliary: Updates smooth terrain sculpt sphere preview.
	_ghost_view.hide_axis()
	if not hit.get("hit", false):
		_ghost_view.hide_all()
		return
	var is_erase: bool = Input.is_key_pressed(KEY_SHIFT)
	_ghost_view.show_sphere(hit.get("point", Vector3.ZERO), _sculpt_radius, is_erase)


func _ghost_furniture(hit: Dictionary) -> void:
	## Auxiliary: Updates furniture placement ghost mesh and rotation axis line.
	if _furniture_defs.is_empty() or _selected_furniture_idx < 0 or _selected_furniture_idx >= _furniture_defs.size():
		_ghost_view.hide_all()
		return
	var def: FurnitureDef = _furniture_defs[_selected_furniture_idx]
	var furn_mesh: Mesh = def.get_mesh() if def != null else null
	if def == null or furn_mesh == null or not hit.get("hit", false):
		_ghost_view.hide_all()
		return
	var anchor: Vector3i = _target_cell(hit, false)
	if anchor == Vector3i.MIN:
		_ghost_view.hide_all()
		return
	var dims: Vector3i = FurnitureLayer.dimensions_of(def)
	var origin: Vector3 = FurnitureLayer.world_origin(anchor, dims, _yaw)
	var is_erase: bool = Input.is_key_pressed(KEY_SHIFT)
	_ghost_view.show_furniture(furn_mesh, origin, _yaw, is_erase)
	if not is_erase:
		_ghost_view.show_axis(origin + Vector3(0, float(dims.y) * 0.5, 0), _active_rotation_axis)
	else:
		_ghost_view.hide_axis()


func _ghost_spawn(hit: Dictionary) -> void:
	## Auxiliary: Updates spawn marker preview capsule.
	_ghost_view.hide_axis()
	if not hit.get("hit", false):
		_ghost_view.hide_all()
		return
	var is_remove: bool = Input.is_key_pressed(KEY_SHIFT) or _selected_spawn_type == "remove"
	var color: Color
	if is_remove:
		color = Color(1.0, 0.4, 0.1, 0.6)
	elif _selected_spawn_type == "player":
		color = Color(0.2, 1.0, 0.2, 0.5)
	elif _selected_spawn_type == "colonist":
		color = Color(0.2, 0.5, 1.0, 0.5)
	elif _selected_spawn_type == "enemy":
		color = Color(1.0, 0.2, 0.2, 0.5)
	else:
		color = Color(0.2, 1.0, 0.2, 0.5)
	_ghost_view.show_capsule(_get_surface_hit_point(hit), color)


func _ghost_structure(hit: Dictionary) -> void:
	## Auxiliary: Updates structure stamping ghost via structure tool.
	_ghost_view.hide_all()
	if not hit.get("hit", false) or _structure_tool == null or _structure_tool.get_active_structure() == null:
		if _structure_tool != null:
			_structure_tool.hide_ghost()
		return
	var cell: Vector3i = _target_cell(hit, false)
	if cell == Vector3i.MIN:
		if _structure_tool != null:
			_structure_tool.hide_ghost()
		return
	_structure_tool.update_ghost_position(cell)


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


func _do_block_paint(hit: Dictionary) -> void:
	# 1. Stored value: resolve base index plus rotation to the renderable variant index (plain base index for unrotated blocks).
	var stored: int = _selected_block_index
	if _block_library != null:
		stored = _block_library.get_stored_index(_selected_block_index, _active_rotation_index)
	# 2. Block stroke: delegate painting to block stroke handler with the resolved block variant index.
	_do_block_stroke(hit, false, stored)


func _do_block_erase(hit: Dictionary) -> void:
	# 1. Block stroke: delegate erasing to block stroke handler with air index 0.
	_do_block_stroke(hit, true, 0)


func _do_block_stroke(hit: Dictionary, erase: bool, value: int) -> void:
	if _map_root == null or _blocky_grid == null or not hit.get("hit", false):
		return
	var cell := _target_cell(hit, erase)
	if cell == Vector3i.MIN:
		return
	# 1. Undo entry: the raw value of every cell in the footprint, captured before the write.
	_history.push({"type": "block", "ops": _collect_block_ops(_brush_box(cell))})
	# 2. Write and persist (async retries, see below).
	_apply_block_brush(cell, value)


func _collect_block_ops(bounds: Array[Vector3i]) -> Array[Dictionary]:
	var ops: Array[Dictionary] = []
	for x in range(bounds[0].x, bounds[1].x + 1):
		for y in range(bounds[0].y, bounds[1].y + 1):
			for z in range(bounds[0].z, bounds[1].z + 1):
				var p := Vector3i(x, y, z)
				ops.append({"pos": p, "old_value": _blocky_grid.get_raw_voxel(p)})
	return ops


## Writes one stroke's footprint and persists it. Terrain blocks stream in
## asynchronously, so a write can miss; it retries with a short delay. The grid is
## captured up front and re-checked after each wait, so unloading or switching
## maps mid-retry ends the stroke instead of dereferencing a freed grid.
func _apply_block_brush(cell: Vector3i, value: int) -> bool:
	const MAX_RETRIES := 5
	const RETRY_DELAY := 0.1
	var grid := _blocky_grid
	if grid == null or _map_root == null:
		return false
	var bounds := _brush_box(cell)
	for attempt in MAX_RETRIES:
		grid.fill_box_raw(bounds[0], bounds[1], value)
		if grid.get_raw_voxel(cell) == value:
			_map_root.get_blocky_terrain().save_modified_blocks()
			_mark_dirty()
			return true
		await Engine.get_main_loop().create_timer(RETRY_DELAY).timeout
		if grid != _blocky_grid or not is_instance_valid(grid):
			return false
	push_warning("MapEditor: block write at %s did not land after %d retries" % [str(cell), MAX_RETRIES])
	return false


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
	_history.push({"type": "terrain", "snapshot": _capture_brush_region(point, _sculpt_radius)})
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
	if _camera != null and _ghost_view != null and _mode == Mode.FURNITURE:
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
	var target_pos := _get_surface_hit_point(hit)
	# 1. Marker: creation, naming and tinting live in SpawnAuthoring.
	_spawns.place(_spawn_kind_for(type), target_pos)
	# 2. MapDef mirrors the single player spawn immediately, as before.
	if type == "player" and _map_def != null:
		_map_def.player_spawn = target_pos
	_update_spawn_hud_counts()
	_mark_dirty()


func _do_spawn_remove(hit: Dictionary) -> void:
	if _map_root == null or not hit.get("hit", false):
		return
	# 1. Spawn Removal: Find and free nearest spawn marker within range.
	var removed := _spawns.remove_nearest(_get_surface_hit_point(hit), SPAWN_REMOVE_RANGE)
	if removed == SpawnMarkerRules.Kind.NONE:
		return
	if removed == SpawnMarkerRules.Kind.PLAYER and _map_def != null:
		_map_def.player_spawn = Vector3.ZERO
	_update_spawn_hud_counts()
	_mark_dirty()


func _spawn_kind_for(type: String) -> SpawnMarkerRules.Kind:
	## Auxiliary: Maps string spawn type identifier to SpawnMarkerRules.Kind enum value.
	match type:
		"player":
			return SpawnMarkerRules.Kind.PLAYER
		"colonist":
			return SpawnMarkerRules.Kind.COLONIST
		"enemy":
			return SpawnMarkerRules.Kind.ENEMY
	return SpawnMarkerRules.Kind.NONE


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
	var c: Dictionary = _spawns.counts()
	_hud.set_spawn_counts(c["player"], c["colonists"], c["enemies"])


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
	_history.push({"type": "structure", "ops": ops, "terrain_snapshot": terrain_snapshot})
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
	if _camera != null and _ghost_view != null and _mode == Mode.BLOCK:
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
	# 1. Block info: Update current block selection, size, and rotation.
	_push_block_info(axis_name)
	# 2. Terrain info: Update active terrain material display and sculpt radius.
	_push_terrain_info()
	# 3. Furniture info: Update active furniture item, rotation, and dimensions.
	_push_furniture_info(axis_name)


func _push_block_info(axis_name: String) -> void:
	## Auxiliary: Pushes selected block name, brush size, and rotation to HUD.
	if _block_library == null:
		return
	var def: BlockDef = _block_library.get_def_by_index(_selected_block_index)
	var block_name := def.display_name if def != null and not def.display_name.is_empty() else (def.id if def != null else "Unknown")
	var block_id := def.id if def != null else ""
	_hud.set_block_info(block_name, _brush_diameter, block_id, _selected_block_index, _active_rotation_index, axis_name)


func _push_terrain_info() -> void:
	## Auxiliary: Pushes selected terrain material and sculpt radius to HUD.
	_hud.set_terrain_info(_terrain_material_display(), _sculpt_radius)


func _push_furniture_info(axis_name: String) -> void:
	## Auxiliary: Pushes selected furniture name, yaw, dimensions, and axis to HUD.
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
	var player_pos: Variant = _spawns.player_position()
	if player_pos != null:
		_map_def.player_spawn = player_pos
	_map_def.enemy_spawns = _spawns.enemy_spawns()


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
	var def_path := MapRepository.MAPS_DIR + _map_def.id + "/map_def.tres"
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
	if _camera != null and _ghost_view != null and (_mode == Mode.BLOCK or _mode == Mode.FURNITURE):
		var hit := _raycast_from_camera()
		_update_ghost(hit)


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
