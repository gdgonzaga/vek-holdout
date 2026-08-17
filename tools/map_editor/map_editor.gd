class_name MapEditor
extends Node3D
## Standalone WYSIWYG dual-voxel map authoring environment.
##
## Loads both blocky structures and smooth Transvoxel terrain at runtime,
## providing fly-camera navigation, WYSIWYG visual verification, and
## map creation/loading lifecycle.

const EditorHUDClass = preload("res://tools/map_editor/editor_hud.gd")
const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")

const MAPS_DIR: String = "res://data/maps/"
const TEMPLATE_PATH: String = "res://subsystems/maps/map_template.tscn"
const DEFAULT_TERRAIN_GEN: String = "res://data/terrain/default_ground.tres"

const FLY_SPEED: float = 8.0
const FLY_SPEED_FAST: float = 20.0
const MOUSE_SENSITIVITY: float = 0.2

enum Mode {
	NAVIGATE,
	BLOCK,
	TERRAIN,
	FURNITURE,
	SPAWN,
}

var _mode: Mode = Mode.NAVIGATE
var _map_root: Map = null
var _map_def: MapDef = null
var _map_scene_path: String = ""

var _camera: Camera3D = null
var _viewer: VoxelViewer = null
var _hud: EditorHUD = null
var _launcher: EditorLauncher = null
var _dirty: bool = false

var _blocky_grid: BlockyGrid = null
var _block_vt: VoxelTool = null
var _block_library: BlockLibrary = null
var _selected_block_index: int = 6 # Default 6 = wood
var _brush_radius: float = 1.0
var _ghost: MeshInstance3D = null
var _ghost_mat: StandardMaterial3D = null

var _cam_yaw: float = 0.0
var _cam_pitch: float = -30.0


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_ghost()
	_block_library = BlockLibrary.new()

	_hud = EditorHUDClass.new()
	add_child(_hud)
	_hud.setup(self)
	_hud.set_mode(_mode)
	_hud.hide()

	_launcher = EditorLauncherClass.new()
	add_child(_launcher)
	_launcher.map_selected.connect(load_map)
	_launcher.new_map_requested.connect(func(name_str: String, type_int: int) -> void:
		create_new_map(name_str, type_int)
	)
	_launcher.setup(_scan_maps())
	_launcher.show_launcher()


func _input(event: InputEvent) -> void:
	# If launcher is open, ignore camera input
	if _launcher != null and _launcher.visible:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				elif _mode == Mode.BLOCK and mb.button_index == MOUSE_BUTTON_LEFT:
					var hit := _raycast_from_camera()
					if mb.shift_pressed:
						_do_block_erase(hit)
					else:
						_do_block_paint(hit)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if _mode == Mode.BLOCK and Input.is_key_pressed(KEY_B):
					var dir := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
					_brush_radius = clampf(_brush_radius + dir * 1.0, 1.0, 5.0)
					_update_hud_block_info()
					get_viewport().set_input_as_handled()

	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed:
			if k.keycode == KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					unload_map()
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
			elif k.keycode == KEY_BRACKETLEFT:
				if _mode == Mode.BLOCK:
					_cycle_block(-1)
			elif k.keycode == KEY_BRACKETRIGHT:
				if _mode == Mode.BLOCK:
					_cycle_block(1)
			elif k.keycode == KEY_S and k.ctrl_pressed:
				save_map()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_cam_yaw -= mm.relative.x * MOUSE_SENSITIVITY
			_cam_pitch -= mm.relative.y * MOUSE_SENSITIVITY
			_cam_pitch = clampf(_cam_pitch, -89.0, 89.0)
			_apply_camera_rotation()


func _apply_camera_rotation() -> void:
	if _camera != null:
		_camera.rotation_degrees = Vector3(_cam_pitch, _cam_yaw, 0.0)


func _process(delta: float) -> void:
	if _camera == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if _ghost != null:
			_ghost.visible = false
		return

	if _mode == Mode.BLOCK:
		var hit := _raycast_from_camera()
		_update_ghost(hit)
	else:
		if _ghost != null:
			_ghost.visible = false

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





func load_map(map_id: String) -> void:
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
	add_child(instance)

	_map_root = instance as Map
	_map_def = def
	_map_scene_path = def.scene_path
	_dirty = false

	_blocky_grid = _map_root.blocky_grid
	if _blocky_grid != null:
		_block_vt = _blocky_grid.get_voxel_tool()
		_block_vt.mode = VoxelTool.MODE_SET

	_attach_streams(_map_root, map_id)
	_position_camera_at_spawn()

	if _hud != null:
		_hud.set_map_info(map_id, _dirty)
		_hud.show()
		_update_hud_block_info()

	if _launcher != null:
		_launcher.hide_launcher()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func create_new_map(map_name: String, map_type: int = MapDef.MapType.POI) -> String:
	if map_name.is_empty():
		push_warning("MapEditor: empty map name")
		return ""
	if " " in map_name:
		push_warning("MapEditor: map name must not contain spaces")
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
	_create_map_def(map_name, folder_path, tscn_path, map_type)

	if _launcher != null:
		_launcher.setup(_scan_maps())

	load_map(map_name)
	return tscn_path


func unload_map() -> void:
	if _dirty:
		save_map()
	if _map_root != null:
		_map_root.queue_free()
		_map_root = null
	_map_def = null
	_map_scene_path = ""
	_dirty = false
	_blocky_grid = null
	_block_vt = null
	if _ghost != null:
		_ghost.visible = false

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _hud != null:
		_hud.hide()

	if _launcher != null:
		_launcher.setup(_scan_maps())
		_launcher.show_launcher()


func _inject_terrain_gen(map: Node, def: MapDef) -> void:
	if def.terrain_gen != null and map.get_node_or_null("SmoothGrid") != null:
		var smooth := map.get_node("SmoothGrid") as SmoothGrid
		if smooth != null:
			smooth.terrain_gen = def.terrain_gen


func _attach_streams(map: Node, map_id: String) -> void:
	var m: Map = map as Map
	var blocky_terrain: VoxelTerrain = null
	var smooth_terrain: VoxelTerrain = null

	if m != null:
		blocky_terrain = m.get_blocky_terrain()
		smooth_terrain = m.get_smooth_terrain()

	# Fallback if map._ready hasn't populated @onready fields or non-Map node
	if blocky_terrain == null:
		blocky_terrain = map.get_node_or_null("BlockyGrid/VoxelTerrain") as VoxelTerrain
	if smooth_terrain == null:
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


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "FlyCamera"
	_camera.current = true
	_camera.position = Vector3(0, 15, 15)
	_cam_yaw = 0.0
	_cam_pitch = -30.0
	_apply_camera_rotation()
	add_child(_camera)

	_viewer = VoxelViewer.new()
	_viewer.name = "VoxelViewer"
	_viewer.requires_visuals = true
	if "requires_collision" in _viewer:
		_viewer.set("requires_collision", true)
	_camera.add_child(_viewer)


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.65, 0.75, 0.85)
	sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.2)
	sky_mat.ground_horizon_color = Color(0.65, 0.75, 0.85)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.5

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)


func _scan_maps() -> Array[MapDef]:
	var results: Array[MapDef] = []
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		return results
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir() and not fname.begins_with("."):
			var def_path := MAPS_DIR + fname + "/map_def.tres"
			if ResourceLoader.exists(def_path):
				var def: MapDef = load(def_path) as MapDef
				if def != null:
					results.append(def)
		fname = dir.get_next()
	dir.list_dir_end()
	return results


func _position_camera_at_spawn() -> void:
	if _camera == null:
		return
	var target_pos := Vector3(0, 5, 0)
	if _map_root != null:
		var spawns: Node3D = _map_root.find_child("SpawnPoints") as Node3D
		var player_spawn: Node3D = spawns.find_child("PlayerSpawn") as Node3D if spawns != null else null
		if player_spawn != null:
			target_pos = player_spawn.global_position
		elif _map_def != null and _map_def.player_spawn != Vector3.ZERO:
			target_pos = _map_def.player_spawn

	_camera.global_position = target_pos + Vector3(0, 6, 10)
	_cam_yaw = 0.0
	_cam_pitch = -30.0
	_apply_camera_rotation()


func _stamp_map_scene(src_path: String, dst_path: String, db_path: String) -> void:
	var packed: PackedScene = load(src_path)
	if packed == null:
		push_error("MapEditor: could not load template '%s'" % src_path)
		return
	var instance: Node = packed.instantiate()
	var terrain := instance.get_node_or_null("BlockyGrid/VoxelTerrain") as VoxelTerrain
	if terrain != null:
		var stream := VoxelStreamSQLite.new()
		stream.database_path = db_path
		terrain.stream = stream
	else:
		push_warning("MapEditor: stamped map has no BlockyGrid/VoxelTerrain")

	var smooth_terrain := instance.get_node_or_null("SmoothGrid/VoxelTerrain") as VoxelTerrain
	if smooth_terrain != null:
		var smooth_stream := VoxelStreamSQLite.new()
		smooth_stream.database_path = db_path.get_base_dir().path_join("terrain.sqlite")
		smooth_terrain.stream = smooth_stream

	var out := PackedScene.new()
	out.pack(instance)
	var err := ResourceSaver.save(out, dst_path)
	if err != OK:
		push_warning("MapEditor: failed to write '%s' (error %d)" % [dst_path, err])
	instance.queue_free()


func _create_map_def(map_name: String, folder_path: String, tscn_path: String, \
		map_type: int = MapDef.MapType.POI) -> void:
	var def := MapDef.new()
	def.id = map_name
	def.display_name = map_name.capitalize()
	def.description = "Authored via Map Editor."
	def.map_type = map_type
	def.scene_path = tscn_path
	var terrain_gen: TerrainGenDef = load(DEFAULT_TERRAIN_GEN) as TerrainGenDef
	if terrain_gen != null:
		def.terrain_gen = terrain_gen
	else:
		push_warning("MapEditor: missing " + DEFAULT_TERRAIN_GEN \
				+ " — new map starts without natural terrain")
	var tres_path := folder_path + "map_def.tres"
	var err := ResourceSaver.save(def, tres_path)
	if err != OK:
		push_warning("MapEditor: failed to write map_def.tres (error %d)" % err)


func _set_mode(new_mode: Mode) -> void:
	_mode = new_mode
	if _hud != null:
		_hud.set_mode(_mode)
		_update_hud_block_info()


func _build_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
	_ghost = MeshInstance3D.new()
	_ghost.name = "EditorGhost"
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.0, 1.0, 1.0)
	_ghost.mesh = box_mesh
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.0, 1.0, 0.0, 0.4)
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	add_child(_ghost)


func _update_ghost(hit: Dictionary) -> void:
	if _ghost == null or _mode != Mode.BLOCK:
		if _ghost != null:
			_ghost.visible = false
		return

	if not hit.get("hit", false):
		_ghost.visible = false
		return

	_ghost.visible = true
	var is_erase := Input.is_key_pressed(KEY_SHIFT)
	var cell_pos := Vector3i.ZERO

	var surface: String = hit.get("surface", "")
	if is_erase:
		if surface == "blocky":
			cell_pos = hit.get("position", Vector3i.ZERO)
		else:
			_ghost.visible = false
			return
	else:
		if surface == "blocky" or surface == "body":
			cell_pos = hit.get("position", Vector3i.ZERO) + hit.get("normal", Vector3i.ZERO)
		elif surface == "smooth":
			cell_pos = hit.get("position", Vector3i.ZERO)
		else:
			_ghost.visible = false
			return

	var terrain := _map_root.get_blocky_terrain() if _map_root != null else null
	var cell_center: Vector3 = Vector3(cell_pos) + Vector3(0.5, 0.5, 0.5)
	if terrain != null:
		_ghost.global_position = terrain.to_global(cell_center)
	else:
		_ghost.global_position = cell_center

	if not _ghost.mesh is BoxMesh:
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 1.0, 1.0)
		_ghost.mesh = box

	var scale_factor := (_brush_radius * 2.0 - 1.0) if _brush_radius > 1.0 else 1.0
	_ghost.scale = Vector3(scale_factor, scale_factor, scale_factor)

	if _ghost_mat != null:
		if is_erase:
			_ghost_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.4)
		else:
			_ghost_mat.albedo_color = Color(0.0, 1.0, 0.0, 0.4)


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


func _do_block_paint(hit: Dictionary) -> void:
	if _map_root == null or _block_vt == null:
		return
	if not hit.get("hit", false):
		return

	var surface: String = hit.get("surface", "")
	var cell_pos := Vector3i.ZERO
	if surface == "blocky" or surface == "body":
		cell_pos = hit.get("position", Vector3i.ZERO) + hit.get("normal", Vector3i.ZERO)
	elif surface == "smooth":
		cell_pos = hit.get("position", Vector3i.ZERO)
	else:
		return

	const MAX_RETRIES := 5
	const RETRY_DELAY := 0.1
	_block_vt.value = _selected_block_index
	var center: Vector3 = _map_root.get_blocky_terrain().to_global(Vector3(cell_pos) + Vector3(0.5, 0.5, 0.5))

	for attempt in MAX_RETRIES:
		if _brush_radius <= 1.0:
			_block_vt.set_voxel(cell_pos, _selected_block_index)
		else:
			var r := int(_brush_radius) - 1
			_block_vt.do_box(cell_pos - Vector3i(r, r, r), cell_pos + Vector3i(r + 1, r + 1, r + 1))
		if _block_vt.get_voxel(cell_pos) == _selected_block_index:
			_map_root.get_blocky_terrain().save_modified_blocks()
			_dirty = true
			if _hud != null and _map_def != null:
				_hud.set_map_info(_map_def.id, _dirty)
			return
		await Engine.get_main_loop().create_timer(RETRY_DELAY).timeout

	push_warning("MapEditor: write at %s did not land after %d retries" % [str(cell_pos), MAX_RETRIES])


func _do_block_erase(hit: Dictionary) -> void:
	if _map_root == null or _block_vt == null:
		return
	if not hit.get("hit", false) or hit.get("surface", "") != "blocky":
		return

	var cell_pos: Vector3i = hit.get("position", Vector3i.ZERO)
	const MAX_RETRIES := 5
	const RETRY_DELAY := 0.1
	_block_vt.value = 0
	var center: Vector3 = _map_root.get_blocky_terrain().to_global(Vector3(cell_pos) + Vector3(0.5, 0.5, 0.5))

	for attempt in MAX_RETRIES:
		if _brush_radius <= 1.0:
			_block_vt.set_voxel(cell_pos, 0)
		else:
			var r := int(_brush_radius) - 1
			_block_vt.do_box(cell_pos - Vector3i(r, r, r), cell_pos + Vector3i(r + 1, r + 1, r + 1))
		if _block_vt.get_voxel(cell_pos) == 0:
			_map_root.get_blocky_terrain().save_modified_blocks()
			_dirty = true
			if _hud != null and _map_def != null:
				_hud.set_map_info(_map_def.id, _dirty)
			return
		await Engine.get_main_loop().create_timer(RETRY_DELAY).timeout

	push_warning("MapEditor: erase at %s did not land after %d retries" % [str(cell_pos), MAX_RETRIES])


func _cycle_block(dir: int) -> void:
	if _block_library == null:
		return
	var indices: Array = []
	for idx in _block_library._defs_by_index.keys():
		indices.append(idx)
	indices.sort()
	if indices.is_empty():
		return
	var cur_pos := indices.find(_selected_block_index)
	if cur_pos == -1:
		cur_pos = 0
	cur_pos = (cur_pos + dir) % indices.size()
	if cur_pos < 0:
		cur_pos += indices.size()
	_selected_block_index = indices[cur_pos]
	_update_hud_block_info()


func _update_hud_block_info() -> void:
	if _hud != null and _block_library != null:
		var def: BlockDef = _block_library.get_def_by_index(_selected_block_index)
		var block_name := def.id if def != null else "Unknown"
		_hud.set_block_info(block_name, _brush_radius)


func save_map() -> void:
	if _map_root != null:
		_map_root.flush_voxel_streams()
		_dirty = false
		if _hud != null and _map_def != null:
			_hud.set_map_info(_map_def.id, _dirty)