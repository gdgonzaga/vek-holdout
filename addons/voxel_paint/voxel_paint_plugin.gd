@tool
extends EditorPlugin
class_name VoxelPaintPlugin
## WYSIWYG voxel painter for zylann VoxelTerrain.
##
## Toolbar button appears when a VoxelTerrain is selected. LMB paints, Shift+LMB
## (or Erase mode) removes. Writes integer voxel indices via VoxelTool (same path
## as the proven persistence experiment — Fact 2) and flushes with
## VoxelTerrain.save_modified_blocks() so edits persist through the terrain's
## VoxelStreamSQLite.
##
## Block indices (from BlockLibrary, stable): 0 air, 1 terrain, 2 metal,
## 3 reinforced, 4 scrap, 5 stone, 6 wood.
##
## Hit detection uses a get_voxel() RAY-MARCH along the camera ray — NOT a Godot
## physics raycast and NOT VoxelTool.raycast(). Both of those are dead in the
## editor viewport: VoxelTerrain emits no chunks/collision/mesh there (Fact 4),
## so intersect_ray has nothing to hit and VoxelTool.raycast returns null. The
## march samples the generator's data layer directly, which IS queryable.

const MARCH_STEP := 0.25
const MARCH_MAX_STEPS := 256
const RETRY_DELAY := 0.1
const MAX_RETRIES := 5

# Furniture placement constants
const FURNITURE_ROTATE_KEY := KEY_R

# Modes
enum PaintMode {
	PAINT,
	ERASE,
	FURNITURE
}

# Preload the FurnitureAuthoring script
const FurnitureAuthoring = preload("res://addons/voxel_paint/furniture_authoring.gd")

var _toolbar_btn: Button
var _panel: PanelContainer
var _active: bool = false
var _terrain: VoxelTerrain
var _vt: VoxelTool
var _block_lib: BlockLibrary
var _brush_radius: float = 2.0
var _current_index: int = 6
var _erase: bool = false
var _first_stroke: bool = true
var _map_root: Node = null  # The Map node owning SpawnPoints
var _furniture: FurnitureAuthoring = null  # Editor marker helper
var _mode: int = PaintMode.PAINT  # Single source of truth

# Furniture rotation state
var _yaw: int = 0  # 0..3, cycled by R key


func _enter_tree() -> void:
	_toolbar_btn = Button.new()
	_toolbar_btn.text = "Voxel Paint"
	_toolbar_btn.toggle_mode = true
	_toolbar_btn.toggled.connect(_on_toggle)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_btn)
	_toolbar_btn.visible = false


func _exit_tree() -> void:
	_deactivate()
	if _toolbar_btn:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_btn)
		_toolbar_btn.queue_free()


func _handles(object: Object) -> bool:
	return object is VoxelTerrain


func _edit(object: Object) -> void:
	_toolbar_btn.visible = object is VoxelTerrain
	if not (object is VoxelTerrain):
		if _toolbar_btn.button_pressed:
			_toolbar_btn.set_pressed_no_signal(false)


func _make_visible(visible: bool) -> void:
	_toolbar_btn.visible = visible


func _on_toggle(pressed: bool) -> void:
	if pressed:
		var sel := EditorInterface.get_selection().get_selected_nodes()
		_terrain = sel.front() as VoxelTerrain if not sel.is_empty() else null
		if _terrain == null:
			_toolbar_btn.set_pressed_no_signal(false)
			return
		_activate()
	else:
		_deactivate()


func _activate() -> void:
	_active = true
	_first_stroke = true
	_ensure_library()
	_vt = _terrain.get_voxel_tool()
	_vt.mode = VoxelTool.MODE_SET
	_panel = preload("res://addons/voxel_paint/voxel_paint_panel.gd").new()
	_panel.setup(self)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _panel)

	# Resolve map root and SpawnPoints for furniture mode.
	# Walk up to the edited scene root — _terrain.get_parent() is VoxelGrid,
	# its parent is the Map node that owns SpawnPoints.
	_yaw = 0
	_map_root = get_editor_interface().get_edited_scene_root()
	if _map_root == null:
		_map_root = _terrain.get_parent().get_parent()
	elif not _map_root.has_node("SpawnPoints"):
		# Edited root isn't the map — fall back to terrain's grandparent.
		_map_root = _terrain.get_parent().get_parent()
	if _map_root and _furniture == null:
		var furniture_auth := FurnitureAuthoring.new()
		if furniture_auth.bind(_map_root):
			_furniture = furniture_auth
		else:
			# Disable furniture mode if bind failed (no SpawnPoints).
			if _panel and _panel.has_method("set_furniture_enabled"):
				_panel.set_furniture_enabled(false)


func _deactivate() -> void:
	_active = false
	if _panel:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _panel)
		_panel.queue_free()
		_panel = null
	_terrain = null
	_vt = null
	_map_root = null
	if _furniture:
		_furniture.unbind()
		_furniture = null


func _ensure_library() -> void:
	if _block_lib == null:
		_block_lib = BlockLibrary.new()
	if _terrain.mesher != null and _terrain.mesher.library == null:
		_terrain.mesher.library = _block_lib.get_voxel_library()


# --- Stream management (called by panel) ------------------------------------

## Returns the current database path, or "" if no stream is assigned.
func get_stream_path() -> String:
	if _terrain != null and _terrain.stream is VoxelStreamSQLite:
		return _terrain.stream.database_path
	return ""


## Creates a new map folder in data/maps/ with an empty SQLite database,
## assigns the stream to the terrain, and writes a map_def.tres catalog entry
## (scene_path -> map_template.tscn). Returns the database path, or "" if the
## map already exists or the folder could not be created.
func create_new_map(map_name: String) -> String:
	if map_name.is_empty():
		push_warning("VoxelPaint: empty map name")
		return ""
	var folder_path := "res://data/maps/%s/" % map_name
	if DirAccess.dir_exists_absolute(folder_path):
		push_warning("VoxelPaint: map '%s' already exists" % map_name)
		return ""
	var err := DirAccess.make_dir_recursive_absolute(folder_path.trim_suffix("/"))
	if err != OK:
		push_warning("VoxelPaint: failed to create folder '%s' (error %d)" % [map_name, err])
		return ""
	var db_path := folder_path + "map.sqlite"
	_assign_stream(db_path)
	_create_map_def(map_name, folder_path)
	return db_path


## Writes a map_def.tres for a freshly authored map. Defaults: map_type POI,
## scene_path -> the shared map_template.tscn. Caller can edit the .tres later.
func _create_map_def(map_name: String, folder_path: String) -> void:
	var def := MapDef.new()
	def.id = map_name
	def.display_name = map_name.capitalize()
	def.description = "Authored via voxel paint."
	def.map_type = MapDef.MapType.POI
	def.scene_path = "res://subsystems/maps/map_template.tscn"
	var tres_path := folder_path + "map_def.tres"
	var save_err := ResourceSaver.save(def, tres_path)
	if save_err != OK:
		push_warning("VoxelPaint: failed to write map_def.tres (error %d)" % save_err)
		return
	# Make the new resource visible in the editor's FileSystem dock.
	EditorInterface.get_resource_filesystem().scan()


## Creates a VoxelStreamSQLite with the given path and assigns it to the terrain.
func set_stream(path: String) -> void:
	_assign_stream(path)


func _assign_stream(path: String) -> void:
	var stream := VoxelStreamSQLite.new()
	stream.database_path = path
	_terrain.stream = stream
	EditorInterface.save_scene()
	# Notify the panel to refresh its label.
	if _panel and _panel.has_method("refresh_stream_label"):
		_panel.refresh_stream_label()


# --- Input handling ---------------------------------------------------------

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _active or _vt == null:
		return AFTER_GUI_INPUT_PASS

	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if not mb.pressed:
			return AFTER_GUI_INPUT_PASS

		if _panel:
			_brush_radius = _panel.get_brush_radius()

		# Mode is the single source of truth on the panel — read it here rather
		# than mirroring into a plugin member that can drift out of sync.
		var mode: int = _panel.get_mode() if _panel else PaintMode.PAINT
		match mode:
			PaintMode.PAINT:
				_current_index = _panel.get_current_index() if _panel else 6
				var hit := _march_to_voxel(camera, mb.position)
				if hit.get("hit", false):
					var target: Vector3i = hit.prev if mb.shift_pressed else hit.solid
					var value: int = 0 if mb.shift_pressed else _current_index
					_paint_with_retry(target, value)
				return AFTER_GUI_INPUT_STOP

			PaintMode.ERASE:
				var hit := _march_to_voxel(camera, mb.position)
				if hit.get("hit", false):
					var target: Vector3i = hit.solid if mb.shift_pressed else hit.prev
					_paint_with_retry(target, 0)
				return AFTER_GUI_INPUT_STOP

			PaintMode.FURNITURE:
				if _furniture == null:
					return AFTER_GUI_INPUT_PASS
				var hit := _march_to_voxel(camera, mb.position)
				if hit.get("hit", false):
					if mb.shift_pressed:
						# Shift+LMB: remove furniture at the solid surface cell.
						if _furniture.remove_at(hit.solid):
							EditorInterface.save_scene()
					else:
						# LMB: place furniture at the air cell in front of surface.
						var def: FurnitureDef = _panel.get_selected_furniture_def() if _panel else null
						if def and _furniture.place(def, hit.prev, _yaw):
							EditorInterface.save_scene()
				return AFTER_GUI_INPUT_STOP

	# Default behavior: pass through
	return AFTER_GUI_INPUT_PASS


func _input(event: InputEvent) -> void:
	if not _active or _furniture == null:
		return
	# Furniture-only key handling; bail unless the panel is in furniture mode.
	if _panel == null or _panel.get_mode() != PaintMode.FURNITURE:
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				FURNITURE_ROTATE_KEY:
					# Rotate the currently selected marker, or just cycle yaw.
					var selection := get_editor_interface().get_selection()
					if selection.get_selected_nodes().size() > 0:
						var selected_node = selection.get_selected_nodes()[0]
						if selected_node is Marker3D and selected_node.name.begins_with("Furniture_"):
							_furniture.rotate_selected(selected_node)
							EditorInterface.save_scene()
							return
					# No furniture selected — just cycle the yaw for next placement.
					_yaw = (_yaw + 1) % 4

				KEY_DELETE:
					# Delete selected furniture marker.
					var selection := get_editor_interface().get_selection()
					if selection.get_selected_nodes().size() > 0:
						var selected_node = selection.get_selected_nodes()[0]
						if selected_node is Marker3D and selected_node.name.begins_with("Furniture_"):
							var anchor: Vector3i = selected_node.get_meta("anchor", Vector3i())
							if _furniture.remove_at(anchor):
								EditorInterface.save_scene()


# --- Implementation Methods -------------------------------------------------

func _paint_with_retry(voxel_pos: Vector3i, value: int) -> void:
	for attempt in MAX_RETRIES:
		if _first_stroke:
			_validate_transform()
			_first_stroke = false
		_paint_sphere(voxel_pos, value)
		if _vt.get_voxel(voxel_pos) == value:
			_terrain.save_modified_blocks()
			return
		await Engine.get_main_loop().create_timer(RETRY_DELAY).timeout
	push_warning("VoxelPaint: write at %s did not land after %d retries" \
			% [str(voxel_pos), MAX_RETRIES])


func _paint_sphere(voxel_pos: Vector3i, value: int) -> void:
	_vt.value = value
	var center := _terrain.to_global(Vector3(voxel_pos))
	_vt.do_sphere(center, _brush_radius)


func _validate_transform() -> void:
	var origin_world := _terrain.to_global(Vector3.ZERO)
	if origin_world != Vector3.ZERO or _terrain.global_transform.basis != Basis.IDENTITY:
		push_warning("VoxelPaint: terrain has non-identity transform (origin=%s). " \
				+ "do_sphere uses world-space center; verify brush alignment." \
				% str(origin_world))


func _march_to_voxel(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var prev_air := Vector3i()
	for i in MARCH_MAX_STEPS:
		var p: Vector3 = origin + dir * (MARCH_STEP * i)
		var local: Vector3 = _terrain.to_local(p)
		var vpos := Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
		var voxel := _vt.get_voxel(vpos)
		if voxel != 0:
			return {"hit": true, "solid": vpos, "prev": prev_air}
		prev_air = vpos
	return {"hit": false}
