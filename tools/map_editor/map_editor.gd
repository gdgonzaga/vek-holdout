class_name MapEditor
extends Node3D
## Standalone WYSIWYG dual-voxel map authoring environment.
##
## Loads both blocky structures and smooth Transvoxel terrain at runtime,
## providing fly-camera navigation, WYSIWYG visual verification, block/terrain
## sculpting, furniture authoring, spawn point management, and map lifecycle.

const EditorHUDClass = preload("res://tools/map_editor/editor_hud.gd")
const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")
const FurnitureAuthoringClass = preload("res://addons/voxel_paint/furniture_authoring.gd")

const MAPS_DIR: String = "res://data/maps/"
const TEMPLATE_PATH: String = "res://subsystems/maps/map_template.tscn"
const DEFAULT_TERRAIN_GEN: String = "res://data/terrain/default_ground.tres"

const FLY_SPEED: float = 8.0
const FLY_SPEED_FAST: float = 20.0
const MOUSE_SENSITIVITY: float = 0.2

## Largest brush edge length B+scroll can reach in block mode.
const MAX_BRUSH_DIAMETER: int = 11
## Min/max sculpt radius for smooth terrain mode.
const MIN_SCULPT_RADIUS: float = 0.5
const MAX_SCULPT_RADIUS: float = 5.0

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
var _brush_diameter: int = 1 # Brush edge length in blocks (B+scroll)

var _smooth_grid: SmoothGrid = null
var _smooth_vt: VoxelTool = null
var _sculpt_radius: float = 2.0
var _terrain_material_id: String = "ground"

var _furniture_auth: FurnitureAuthoring = null
var _furniture_defs: Array[FurnitureDef] = []
var _selected_furniture_idx: int = 0
var _yaw: int = 0 # Quarter turns (0..3)
var _spawn_markers: Dictionary = {"player": null, "colonists": []}

var _ghost: MeshInstance3D = null
var _ghost_mat: StandardMaterial3D = null
var _box_mesh: BoxMesh = null
var _sphere_mesh: SphereMesh = null
var _capsule_mesh: CapsuleMesh = null

var _cam_yaw: float = 0.0
var _cam_pitch: float = -30.0


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_ghost()
	_block_library = BlockLibrary.new()
	_furniture_defs = _load_furniture_defs()
	_furniture_auth = FurnitureAuthoringClass.new()

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
	# If launcher is open, ignore camera/edit input
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
				elif _mode == Mode.TERRAIN and mb.button_index == MOUSE_BUTTON_LEFT:
					var hit := _raycast_terrain()
					if mb.shift_pressed:
						_do_terrain_carve(hit)
					else:
						_do_terrain_add(hit)
				elif _mode == Mode.FURNITURE and mb.button_index == MOUSE_BUTTON_LEFT:
					var hit := _raycast_from_camera()
					if mb.shift_pressed:
						_do_furniture_remove(hit)
					else:
						_do_furniture_place(hit)
				elif _mode == Mode.SPAWN and mb.button_index == MOUSE_BUTTON_LEFT:
					var hit := _raycast_from_camera()
					if mb.shift_pressed:
						_do_spawn_place("colonist", hit)
					else:
						_do_spawn_place("player", hit)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if Input.is_key_pressed(KEY_B):
					var dir := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
					if _mode == Mode.BLOCK:
						_brush_diameter = clampi(_brush_diameter + int(dir), 1, MAX_BRUSH_DIAMETER)
					elif _mode == Mode.TERRAIN:
						_sculpt_radius = clampf(_sculpt_radius + dir * 0.5, MIN_SCULPT_RADIUS, MAX_SCULPT_RADIUS)
					_update_hud_info()
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
				elif _mode == Mode.TERRAIN:
					_sculpt_radius = clampf(_sculpt_radius - 0.5, MIN_SCULPT_RADIUS, MAX_SCULPT_RADIUS)
					_update_hud_info()
				elif _mode == Mode.FURNITURE:
					_cycle_furniture(-1)
			elif k.keycode == KEY_BRACKETRIGHT:
				if _mode == Mode.BLOCK:
					_cycle_block(1)
				elif _mode == Mode.TERRAIN:
					_sculpt_radius = clampf(_sculpt_radius + 0.5, MIN_SCULPT_RADIUS, MAX_SCULPT_RADIUS)
					_update_hud_info()
				elif _mode == Mode.FURNITURE:
					_cycle_furniture(1)
			elif k.keycode == KEY_TAB and _mode == Mode.FURNITURE:
				var dir := -1 if k.shift_pressed else 1
				_cycle_furniture(dir)
				get_viewport().set_input_as_handled()
			elif k.keycode == KEY_R and _mode == Mode.FURNITURE:
				_do_furniture_rotate()
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
	elif _mode == Mode.TERRAIN:
		var hit := _raycast_terrain()
		_update_ghost(hit)
	elif _mode == Mode.FURNITURE:
		var hit := _raycast_from_camera()
		_update_ghost(hit)
	elif _mode == Mode.SPAWN:
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

	_smooth_grid = _map_root.get_smooth_grid()
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
		_hud.set_map_info(map_id, _dirty)
		_hud.set_terrain_available(_smooth_grid != null)
		_hud.show()
		_update_hud_info()

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
		push_warning("MapEditor: unloading with unsaved changes")

	if _furniture_auth != null:
		_furniture_auth.unbind()
	_spawn_markers = {"player": null, "colonists": []}

	if _map_root != null:
		_map_root.queue_free()
		_map_root = null

	_map_def = null
	_map_scene_path = ""
	_dirty = false

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
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	add_child(sun)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "EditorCamera"
	_camera.current = true
	_camera.fov = 70.0
	_camera.position = Vector3(0, 10, 20)
	add_child(_camera)

	_viewer = VoxelViewer.new()
	_viewer.name = "EditorViewer"
	_camera.add_child(_viewer)


func _inject_terrain_gen(map: Node, def: MapDef) -> void:
	var smooth: SmoothGrid = map.get_node_or_null("SmoothGrid") as SmoothGrid
	if smooth != null:
		smooth.terrain_gen = def.terrain_gen


func _attach_streams(map: Node, map_id: String) -> void:
	var folder := MAPS_DIR + map_id + "/"
	var blocky_terrain := map.get_node_or_null("BlockyGrid/VoxelTerrain") as VoxelTerrain
	if blocky_terrain != null:
		var stream := VoxelStreamSQLite.new()
		stream.database_path = folder + "map.sqlite"
		blocky_terrain.stream = stream

	var smooth_terrain := map.get_node_or_null("SmoothGrid/VoxelTerrain") as VoxelTerrain
	if smooth_terrain != null:
		var smooth_stream := VoxelStreamSQLite.new()
		smooth_stream.database_path = folder + "terrain.sqlite"
		smooth_terrain.stream = smooth_stream


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
		push_warning("MapEditor: failed to write '%s'" % dst_path)
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
		_update_hud_info()


func _build_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
	_ghost = MeshInstance3D.new()
	_ghost.name = "EditorGhost"

	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(1.0, 1.0, 1.0)

	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radius = 1.0
	_sphere_mesh.height = 2.0

	_capsule_mesh = CapsuleMesh.new()
	_capsule_mesh.radius = 0.4
	_capsule_mesh.height = 1.8

	_ghost.mesh = _box_mesh
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.0, 1.0, 0.0, 0.4)
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	add_child(_ghost)


## Previews placement/carve target:
## Block mode: BoxMesh scaled to brush diameter at cell center.
## Terrain mode: SphereMesh scaled to sculpt radius at raycast surface point.
## Furniture mode: Selected furniture's mesh preview rotated by _yaw.
## Spawn mode: CapsuleMesh preview (green for player, blue for colonist).
func _update_ghost(hit: Dictionary) -> void:
	if _ghost == null:
		return

	var is_erase := Input.is_key_pressed(KEY_SHIFT)

	if _mode == Mode.BLOCK:
		_ghost.mesh = _box_mesh
		var cell := _target_cell(hit, is_erase)
		if not hit.get("hit", false) or cell == Vector3i.MIN:
			_ghost.visible = false
			return

		_ghost.visible = true
		var bounds := _brush_box(cell)
		var box_center := _box_center(bounds)
		_ghost.global_position = box_center
		_ghost.scale = Vector3(_brush_diameter, _brush_diameter, _brush_diameter)
		_ghost.global_rotation = Vector3.ZERO
		_ghost_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.4) if is_erase else Color(0.0, 1.0, 0.0, 0.4)

	elif _mode == Mode.TERRAIN:
		if _smooth_grid == null or not hit.get("hit", false):
			_ghost.visible = false
			return

		_ghost.mesh = _sphere_mesh
		_ghost.visible = true
		_ghost.global_position = hit.get("point", Vector3.ZERO)
		_ghost.scale = Vector3(_sculpt_radius, _sculpt_radius, _sculpt_radius)
		_ghost.global_rotation = Vector3.ZERO
		_ghost_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.4) if is_erase else Color(0.0, 1.0, 0.0, 0.4)

	elif _mode == Mode.FURNITURE:
		if _furniture_defs.is_empty() or _selected_furniture_idx < 0 or _selected_furniture_idx >= _furniture_defs.size():
			_ghost.visible = false
			return
		var def := _furniture_defs[_selected_furniture_idx]
		if def == null or def.mesh == null or not hit.get("hit", false):
			_ghost.visible = false
			return
		var anchor := _target_cell(hit, false)
		if anchor == Vector3i.MIN:
			_ghost.visible = false
			return
		_ghost.mesh = def.mesh
		_ghost.scale = Vector3.ONE
		var dims := FurnitureLayer.dimensions_of(def)
		var origin := FurnitureLayer.world_origin(anchor, dims, _yaw)
		_ghost.global_position = origin
		_ghost.global_rotation = Vector3(0, deg_to_rad(_yaw * 90), 0)
		_ghost_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.5) if is_erase else Color(0.4, 0.8, 1.0, 0.5)
		_ghost.visible = true

	elif _mode == Mode.SPAWN:
		if not hit.get("hit", false):
			_ghost.visible = false
			return
		_ghost.mesh = _capsule_mesh
		_ghost.scale = Vector3.ONE
		var is_colonist := Input.is_key_pressed(KEY_SHIFT)
		var pos := _get_surface_hit_point(hit)
		_ghost.global_position = pos + Vector3(0, 0.9, 0)
		_ghost.global_rotation = Vector3.ZERO
		_ghost_mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5) if is_colonist else Color(0.2, 1.0, 0.2, 0.5)
		_ghost.visible = true

	else:
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
			_dirty = true
			if _hud != null and _map_def != null:
				_hud.set_map_info(_map_def.id, _dirty)
			return
		await Engine.get_main_loop().create_timer(RETRY_DELAY).timeout

	push_warning("MapEditor: block write at %s did not land after %d retries" % [str(cell), MAX_RETRIES])


func _do_block_paint(hit: Dictionary) -> void:
	if _map_root == null or _block_vt == null or not hit.get("hit", false):
		return
	var cell := _target_cell(hit, false)
	if cell == Vector3i.MIN:
		return
	_apply_block_brush(cell, _selected_block_index)


func _do_block_erase(hit: Dictionary) -> void:
	if _map_root == null or _block_vt == null or not hit.get("hit", false):
		return
	var cell := _target_cell(hit, true)
	if cell == Vector3i.MIN:
		return
	_apply_block_brush(cell, 0)


func _do_terrain_add(hit: Dictionary) -> void:
	if _map_root == null or _smooth_grid == null or not hit.get("hit", false):
		return
	var point: Vector3 = hit.get("point", Vector3.ZERO)
	_smooth_grid.add_material(point, _terrain_material_id, _sculpt_radius)
	var terrain := _map_root.get_smooth_terrain()
	if terrain != null:
		terrain.save_modified_blocks()
	_dirty = true
	if _hud != null and _map_def != null:
		_hud.set_map_info(_map_def.id, _dirty)


func _do_terrain_carve(hit: Dictionary) -> void:
	if _map_root == null or _smooth_grid == null or not hit.get("hit", false):
		return
	var point: Vector3 = hit.get("point", Vector3.ZERO)
	_smooth_grid.carve(point, _sculpt_radius)
	var terrain := _map_root.get_smooth_terrain()
	if terrain != null:
		terrain.save_modified_blocks()
	_dirty = true
	if _hud != null and _map_def != null:
		_hud.set_map_info(_map_def.id, _dirty)


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
		_dirty = true
		if _hud != null and _map_def != null:
			_hud.set_map_info(_map_def.id, _dirty)


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
		_dirty = true
		if _hud != null and _map_def != null:
			_hud.set_map_info(_map_def.id, _dirty)


func _do_furniture_rotate() -> void:
	_yaw = (_yaw + 1) % 4
	_update_hud_info()


func _cycle_furniture(dir: int) -> void:
	if _furniture_defs.is_empty():
		return
	_selected_furniture_idx = (_selected_furniture_idx + dir) % _furniture_defs.size()
	if _selected_furniture_idx < 0:
		_selected_furniture_idx += _furniture_defs.size()
	_update_hud_info()


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
			player_marker = spawn_points.find_child("PlayerSpawn") as Marker3D
			if player_marker == null:
				player_marker = Marker3D.new()
				player_marker.name = "PlayerSpawn"
				spawn_points.add_child(player_marker)
				player_marker.owner = _map_root
			_spawn_markers["player"] = player_marker
		player_marker.global_position = target_pos
		_visualize_spawn(player_marker, Color(0.2, 1.0, 0.2, 0.5))
		if _map_def != null:
			_map_def.player_spawn = target_pos
		_dirty = true

	elif type == "colonist":
		var next_idx := 1
		for child in spawn_points.get_children():
			if child.name.begins_with("ColonistSpawn"):
				var suffix := child.name.trim_prefix("ColonistSpawn_").trim_prefix("ColonistSpawn")
				if suffix.is_valid_int():
					next_idx = maxi(next_idx, int(suffix) + 1)
				else:
					next_idx = maxi(next_idx, 2)
		var marker := Marker3D.new()
		marker.name = "ColonistSpawn_%d" % next_idx
		spawn_points.add_child(marker)
		marker.owner = _map_root
		marker.global_position = target_pos
		_visualize_spawn(marker, Color(0.2, 0.5, 1.0, 0.5))
		var col_list: Array = _spawn_markers.get("colonists", [])
		col_list.append(marker)
		_spawn_markers["colonists"] = col_list
		_dirty = true

	if _hud != null and _map_def != null:
		_hud.set_map_info(_map_def.id, _dirty)


func _load_furniture_defs() -> Array[FurnitureDef]:
	var out: Array[FurnitureDef] = []
	var dir_path := "res://data/furniture/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("MapEditor: could not open " + dir_path)
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res = load(dir_path + fname)
			if res is FurnitureDef:
				out.append(res as FurnitureDef)
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: FurnitureDef, b: FurnitureDef) -> bool:
		return a.id < b.id
	)
	return out


func _cache_spawn_markers() -> void:
	_spawn_markers = {
		"player": null,
		"colonists": [],
	}
	if _map_root == null:
		return
	var spawns: Node3D = _map_root.find_child("SpawnPoints") as Node3D
	if spawns == null:
		return
	for child in spawns.get_children():
		if child is Marker3D:
			if child.name == "PlayerSpawn":
				_spawn_markers["player"] = child
				_visualize_spawn(child, Color(0.2, 1.0, 0.2, 0.5))
			elif child.name.begins_with("ColonistSpawn"):
				_spawn_markers["colonists"].append(child)
				_visualize_spawn(child, Color(0.2, 0.5, 1.0, 0.5))


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
	_update_hud_info()


func _update_hud_info() -> void:
	if _hud == null:
		return
	if _block_library != null:
		var def: BlockDef = _block_library.get_def_by_index(_selected_block_index)
		var block_name := def.id if def != null else "Unknown"
		_hud.set_block_info(block_name, _brush_diameter)
	_hud.set_terrain_info(_terrain_material_id, _sculpt_radius)
	if not _furniture_defs.is_empty() and _selected_furniture_idx >= 0 and _selected_furniture_idx < _furniture_defs.size():
		var fdef: FurnitureDef = _furniture_defs[_selected_furniture_idx]
		var fname := fdef.display_name if fdef != null and not fdef.display_name.is_empty() else (fdef.id if fdef != null else "Unknown")
		_hud.set_furniture_info(fname, _yaw)
	else:
		_hud.set_furniture_info("None", _yaw)


func save_map() -> void:
	if _map_root != null:
		_map_root.flush_voxel_streams()

		if _map_def != null:
			if _spawn_markers.get("player") != null and is_instance_valid(_spawn_markers["player"]):
				var ppos: Vector3 = (_spawn_markers["player"] as Marker3D).global_position
				_map_def.player_spawn = ppos
			var def_path := MAPS_DIR + _map_def.id + "/map_def.tres"
			var err_def := ResourceSaver.save(_map_def, def_path)
			if err_def != OK:
				push_warning("MapEditor: failed to save MapDef to '%s' (error %d)" % [def_path, err_def])

		if not _map_scene_path.is_empty():
			var packed := PackedScene.new()
			var err_pack := packed.pack(_map_root)
			if err_pack == OK:
				var err_save := ResourceSaver.save(packed, _map_scene_path)
				if err_save != OK:
					push_warning("MapEditor: failed to save scene to '%s' (error %d)" % [_map_scene_path, err_save])
			else:
				push_warning("MapEditor: failed to pack map scene (error %d)" % err_pack)

		_dirty = false
		if _hud != null and _map_def != null:
			_hud.set_map_info(_map_def.id, _dirty)
