@tool
extends EditorPlugin
class_name VoxelPaintPlugin
## WYSIWYG voxel painter for zylann VoxelTerrain + per-map scene authoring.
##
## Two concerns:
##   1. MAP LIFECYCLE — create/open maps. Each map owns its own .tscn stamped
##      from subsystems/maps/map_template.tscn, with a per-map VoxelStreamSQLite
##      pointing at data/maps/<id>/map.sqlite. Furniture lives as Marker3Ds in
##      that .tscn, so per-map isolation is automatic at runtime (SceneManager
##      scans the loaded scene's SpawnPoints via SpawnHelpers).
##   2. PAINTING — LMB paints, Shift+LMB (or Erase mode) removes voxels;
##      furniture mode places/removes/rotates Furniture_* markers. Bound to the
##      VoxelTerrain of the currently open map scene.
##
## The toolbar button is visible for any node selection so map authoring is
## reachable without first selecting a VoxelTerrain. Painting binds to a terrain
## once one is selected or a map is opened.
##
## Block indices (from BlockLibrary, stable): 0 air, 1 terrain, 2 metal,
## 3 reinforced, 4 scrap, 5 stone, 6 wood.
##
## Hit detection uses a get_voxel() RAY-MARCH along the camera ray — NOT a Godot
## physics raycast and NOT VoxelTool.raycast(). Both of those are dead in the
## editor viewport: VoxelTerrain emits no chunks/collision/mesh there, so
## intersect_ray has nothing to hit and VoxelTool.raycast returns null. The
## march samples the generator's data layer directly, which IS queryable.

const MARCH_STEP := 0.25
const MARCH_MAX_STEPS := 256
const RETRY_DELAY := 0.1
const MAX_RETRIES := 5

# Furniture placement constants
const FURNITURE_ROTATE_KEY := KEY_R

# Map authoring paths.
const TEMPLATE_PATH := "res://subsystems/maps/map_template.tscn"
const MAPS_DIR := "res://data/maps/"

# Default TerrainGenDef stamped into every new map's map_def.tres: natural
# smooth ground (50 m deep rolling terrain) is the initial terrain now that
# the template's blocky layer generates nothing — blocky is structures-only.
# Clear `terrain_gen` in a map_def.tres to opt a map out of natural terrain.
const DEFAULT_TERRAIN_GEN := "res://data/terrain/default_ground.tres"

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
var _brush_radius: float = 1.0
var _current_index: int = 6
var _first_stroke: bool = true
var _map_root: Node = null  # The Map node owning SpawnPoints
var _furniture: FurnitureAuthoring = null  # Editor marker helper
var _mode: int = PaintMode.PAINT  # Single source of truth (read from panel)

# Hover preview ghost.
var _ghost: MeshInstance3D = null  # transient preview, no owner (never saved)
var _ghost_mat: StandardMaterial3D = null  # cached so hover can tint without a cast
var _box_mesh: BoxMesh  # unit-cube mesh reused for block paint/erase previews
var _last_camera: Camera3D = null  # cached so key events can refresh the ghost
var _last_screen_pos: Vector2 = Vector2.ZERO

# Furniture rotation state
var _yaw: int = 0  # 0..3, cycled by R key


func _enter_tree() -> void:
	_toolbar_btn = Button.new()
	_toolbar_btn.text = "Voxel Paint"
	_toolbar_btn.toggle_mode = true
	_toolbar_btn.toggled.connect(_on_toggle)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_btn)


func _exit_tree() -> void:
	_deactivate()
	if _toolbar_btn:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_btn)
		_toolbar_btn.queue_free()


# Claim any node so the toolbar stays visible throughout 3D authoring (selecting
# a furniture marker must not hide the panel). Painting binds to a terrain
# separately, via _edit or open_map_scene.
func _handles(object: Object) -> bool:
	return object is Node


# Bind to a freshly selected terrain; never unbind on other selections so the
# paint target stays stable while the user edits markers etc. Blocky terrains
# only — selecting the smooth terrain must not rebind (see _find_scene_terrain).
func _edit(object: Object) -> void:
	if _active and _is_blocky_terrain(object as Node):
		_bind_terrain(object as VoxelTerrain)


# The toolbar button follows the 3D editor's visibility (hidden in 2D/Script),
# but unlike the old version it no longer requires a VoxelTerrain to be selected
# — the Maps section is reachable from any node selection.
func _make_visible(visible: bool) -> void:
	_toolbar_btn.visible = visible


func _on_toggle(pressed: bool) -> void:
	if pressed:
		_activate()
	else:
		_deactivate()


func _activate() -> void:
	_active = true
	_first_stroke = true
	_ensure_library()
	_panel = preload("res://addons/voxel_paint/voxel_paint_panel.gd").new()
	_panel.setup(self)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _panel)
	# Bind whatever terrain is available: prefer the selection, else the first
	# VoxelTerrain in the open scene. May be null (panel shows a "no terrain"
	# hint and map creation still works).
	_bind_terrain(_find_scene_terrain())


func _deactivate() -> void:
	_active = false
	if _panel:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _panel)
		_panel.queue_free()
		_panel = null
	_unbind_terrain()


func _ensure_library() -> void:
	if _block_lib == null:
		_block_lib = BlockLibrary.new()


# --- Terrain binding --------------------------------------------------------

## Returns the BLOCKY terrain to bind on activation: a selected VoxelTerrain
## owned by a BlockyGrid, else the first such terrain in the edited scene, else
## null. Never binds the smooth terrain — scenes carry two VoxelTerrain nodes
## since the dual-voxel template, both named "VoxelTerrain", so identification
## is by the owning grid's script (never node name/order). In-editor smooth
## painting is impossible anyway: the editor viewport can't render Transvoxel
## terrain (F5), and the paint tool's block model assumes the blocky library.
func _find_scene_terrain() -> VoxelTerrain:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	for n in sel:
		if _is_blocky_terrain(n):
			return n
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		for t in root.find_children("VoxelTerrain", "VoxelTerrain", true, false):
			if _is_blocky_terrain(t):
				return t
	return null


## True when node is a VoxelTerrain parented by a BlockyGrid — the structures
## terrain and the only paintable one. SmoothGrid's terrain parent has
## smooth_grid.gd; unparented terrains (spike scenes) bind nothing.
func _is_blocky_terrain(node: Node) -> bool:
	if node is not VoxelTerrain:
		return false
	var parent := node.get_parent()
	return parent != null and parent.get_script() != null \
		and str(parent.get_script().resource_path) == "res://subsystems/voxel/blocky_grid.gd"


## Bind painting to a terrain. Recreates the ghost + furniture helper; the panel
## is refreshed to reflect terrain availability. No-op if t is null or already
## bound.
func _bind_terrain(t: VoxelTerrain) -> void:
	if t == null or _terrain == t:
		return
	_teardown_paint_attachments()  # drop old ghost/furniture, keep terrain ref
	_terrain = t
	_first_stroke = true
	_vt = _terrain.get_voxel_tool()
	_vt.mode = VoxelTool.MODE_SET
	if _terrain.mesher != null and _terrain.mesher.library == null:
		_terrain.mesher.library = _block_lib.get_voxel_library()
	_resolve_map_root_and_furniture()
	if _active:
		_create_ghost()
	if _panel:
		_panel.refresh_terrain_status()
		_panel.refresh_map_type()


func _unbind_terrain() -> void:
	_teardown_paint_attachments()
	_terrain = null
	_vt = null
	_map_root = null
	if _panel:
		_panel.refresh_terrain_status()
		_panel.refresh_map_type()


## Drop the ghost + furniture binding (the terrain ref is kept by the caller).
func _teardown_paint_attachments() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _furniture:
		_furniture.unbind()
		_furniture = null


## Resolve the map root (scene root owning SpawnPoints) and bind the furniture
## authoring helper to it.
func _resolve_map_root_and_furniture() -> void:
	_yaw = 0
	# Walk up to the edited scene root — _terrain.get_parent() is BlockyGrid,
	# its parent is the Map node that owns SpawnPoints.
	_map_root = EditorInterface.get_edited_scene_root()
	if _map_root == null or not _map_root.has_node("SpawnPoints"):
		# Edited root isn't the map — fall back to terrain's grandparent.
		var p := _terrain.get_parent()
		_map_root = p.get_parent() if p != null else null
	if _map_root and _furniture == null:
		var fa := FurnitureAuthoring.new()
		if fa.bind(_map_root):
			_furniture = fa
			# Re-enable furniture mode — reflects the current map and recovers
			# from an earlier bind failure (e.g. a scene-switch race).
			if _panel and _panel.has_method("set_furniture_enabled"):
				_panel.set_furniture_enabled(true)
		else:
			# Disable furniture mode if bind failed (no SpawnPoints).
			if _panel and _panel.has_method("set_furniture_enabled"):
				_panel.set_furniture_enabled(false)


## Create the hover-preview ghost (no owner → transient, never saved). Mesh is
## swapped per-mode in _refresh_ghost(). Parented to _map_root (a non-selected
## ancestor) so the terrain's selection AABB gizmo doesn't expand to cover it.
func _create_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.name = "__voxel_paint_ghost__"
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.2, 1.0, 0.2, 0.35)
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = _ghost_mat
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_ghost.mesh = _box_mesh
	if _map_root != null:
		_map_root.add_child(_ghost)
	elif _terrain != null:
		_terrain.add_child(_ghost)


# --- Terrain/stream info (read by the panel) --------------------------------

## Returns the bound terrain's database path, or "" if none.
func get_stream_path() -> String:
	if _terrain != null and _terrain.stream is VoxelStreamSQLite:
		return _terrain.stream.database_path
	return ""


## True when a terrain is bound and still live in the scene tree. Clears stale
## references (e.g. after the scene was closed/replaced).
func is_terrain_bound() -> bool:
	if _terrain == null:
		return false
	if not is_instance_valid(_terrain) or not _terrain.is_inside_tree():
		_terrain = null
		_vt = null
		return false
	return true


# --- Open-map metadata (read/written by the panel) --------------------------

## Derive the map_def.tres path for the currently open map scene, or "" if no map
## scene is open. The convention is data/maps/<id>/map.tscn → map_def.tres in the
## same directory.
func _get_open_map_def_path() -> String:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return ""
	var scene_path: String = root.scene_file_path
	if scene_path.is_empty() or not scene_path.begins_with(MAPS_DIR):
		return ""
	var dir := scene_path.get_base_dir()
	return dir + "/map_def.tres"


## Returns the MapType of the currently open map, or -1 if no map is open or its
## def can't be loaded. Used by the panel to populate the type editor.
func get_open_map_type() -> int:
	var def := _load_open_map_def()
	if def == null:
		return -1
	return def.map_type


## Sets map_type on the currently open map's def and saves it. Returns true on
## success. Used by the panel's type editor; keeps the .tres consistent with what
## the author intends (e.g. marking the base map BASE so it isn't a POI target).
func set_open_map_type(type: int) -> bool:
	var def := _load_open_map_def()
	if def == null:
		return false
	def.map_type = type
	var path := _get_open_map_def_path()
	var err := ResourceSaver.save(def, path)
	if err != OK:
		push_warning("VoxelPaint: failed to save map_def.tres (error %d)" % err)
		return false
	EditorInterface.get_resource_filesystem().scan()
	return true


## Load the MapDef for the currently open map scene, or null if none/missing.
func _load_open_map_def() -> MapDef:
	var path := _get_open_map_def_path()
	if path.is_empty() or not ResourceLoader.exists(path, "Resource"):
		return null
	return load(path) as MapDef


# --- Map lifecycle (called by panel) ----------------------------------------

## Scans data/maps/*/map_def.tres and returns catalog entries for the panel:
## [{ id, display_name, scene_path }, ...], sorted by id. Editor-side scan
## (autoloads aren't reliably reachable from @tool context — see _populate_furniture).
func list_maps() -> Array:
	var out: Array = []
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir() and not fname.begins_with("."):
			var def_path := MAPS_DIR + fname + "/map_def.tres"
			if ResourceLoader.exists(def_path, "Resource"):
				var def: MapDef = load(def_path) as MapDef
				if def != null and def.id != "":
					out.append({
						"id": def.id,
						"display_name": def.display_name if def.display_name != "" else def.id,
						"scene_path": def.scene_path,
					})
		fname = dir.get_next()
	out.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	return out


## Create a new map: stamp the template into data/maps/<id>/map.tscn with a
## per-map sqlite stream, write map_def.tres, then open the scene for painting.
## map_type is written to map_def.tres (defaults to POI — most authored maps are
## expedition destinations; pick BASE for the home colony so it doesn't surface
## as a discoverable POI, see expedition_manager.gd get_available_pois).
## Returns the new tscn path, or "" on failure.
func create_new_map(map_name: String, map_type: int = MapDef.MapType.POI) -> String:
	if map_name.is_empty():
		push_warning("VoxelPaint: empty map name")
		return ""
	if " " in map_name:
		push_warning("VoxelPaint: map name must not contain spaces")
		return ""
	var folder_path := MAPS_DIR + map_name + "/"
	if DirAccess.dir_exists_absolute(folder_path):
		push_warning("VoxelPaint: map '%s' already exists" % map_name)
		return ""
	var err := DirAccess.make_dir_recursive_absolute(folder_path.trim_suffix("/"))
	if err != OK:
		push_warning("VoxelPaint: failed to create folder '%s' (error %d)" % [map_name, err])
		return ""
	var tscn_path := folder_path + "map.tscn"
	var db_path := folder_path + "map.sqlite"
	_stamp_map_scene(TEMPLATE_PATH, tscn_path, db_path)
	_create_map_def(map_name, folder_path, tscn_path, map_type)
	EditorInterface.get_resource_filesystem().scan()
	_open_scene_and_bind(tscn_path)
	return tscn_path


## Open an existing map's scene and bind its terrain for painting.
func open_map_scene(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	if not ResourceLoader.exists(scene_path):
		push_warning("VoxelPaint: scene not found '%s'" % scene_path)
		return
	_open_scene_and_bind(scene_path)


## Instantiate the template, inject per-map VoxelStreamSQLite resources, and
## save as a new .tscn. Pure file op — does not touch the currently bound
## terrain. Terrains are addressed by their owning grid's path, NOT by
## find_child("VoxelTerrain") — the scene has two nodes of that name since the
## dual-voxel template (BlockyGrid/VoxelTerrain + SmoothGrid/VoxelTerrain) and
## a name search could bind either.
func _stamp_map_scene(src_path: String, dst_path: String, db_path: String) -> void:
	var packed: PackedScene = load(src_path)
	if packed == null:
		push_error("VoxelPaint: could not load template '%s'" % src_path)
		return
	var instance := packed.instantiate()
	var terrain := instance.get_node_or_null("BlockyGrid/VoxelTerrain") as VoxelTerrain
	if terrain != null:
		var stream := VoxelStreamSQLite.new()
		stream.database_path = db_path
		terrain.stream = stream
	else:
		push_warning("VoxelPaint: stamped map has no BlockyGrid/VoxelTerrain")
	# Second stream slot: the smooth terrain's own db beside map.sqlite. Edits
	# persist into it (F8); production save/load wiring is Phase 4. A missing
	# SmoothGrid (older templates) is tolerated — smooth terrain is optional.
	var smooth_terrain := instance.get_node_or_null("SmoothGrid/VoxelTerrain") as VoxelTerrain
	if smooth_terrain != null:
		var smooth_stream := VoxelStreamSQLite.new()
		smooth_stream.database_path = db_path.get_base_dir().path_join("terrain.sqlite")
		smooth_terrain.stream = smooth_stream
	var out := PackedScene.new()
	out.pack(instance)
	var err := ResourceSaver.save(out, dst_path)
	if err != OK:
		push_warning("VoxelPaint: failed to write '%s' (error %d)" % [dst_path, err])
	instance.queue_free()


## Writes map_def.tres pointing scene_path at the per-map .tscn. map_type defaults
## to POI since most authored maps are expedition content; pass BASE for the
## home colony so it doesn't appear as a discoverable POI. terrain_gen defaults
## to DEFAULT_TERRAIN_GEN so new maps open on natural ground (the template's
## blocky terrain generates nothing); a missing def degrades to a terrain-less
## map rather than failing creation.
func _create_map_def(map_name: String, folder_path: String, tscn_path: String, \
		map_type: int = MapDef.MapType.POI) -> void:
	var def := MapDef.new()
	def.id = map_name
	def.display_name = map_name.capitalize()
	def.description = "Authored via voxel paint."
	def.map_type = map_type
	def.scene_path = tscn_path
	var terrain_gen: TerrainGenDef = load(DEFAULT_TERRAIN_GEN) as TerrainGenDef
	if terrain_gen != null:
		def.terrain_gen = terrain_gen
	else:
		push_warning("VoxelPaint: missing " + DEFAULT_TERRAIN_GEN \
				+ " — new map starts without natural terrain")
	var tres_path := folder_path + "map_def.tres"
	var err := ResourceSaver.save(def, tres_path)
	if err != OK:
		push_warning("VoxelPaint: failed to write map_def.tres (error %d)" % err)


## Open a scene in the editor and bind its terrain once it has loaded. The brief
## timer lets the editor instantiate the new scene before we search its tree.
func _open_scene_and_bind(scene_path: String) -> void:
	EditorInterface.open_scene_from_path(scene_path)
	# Wait until the editor has actually swapped to the new scene before
	# binding — a fixed delay races the scene loader and can bind to the
	# previously open scene instead (which disables furniture authoring).
	for i in MAX_RETRIES:
		await Engine.get_main_loop().create_timer(RETRY_DELAY).timeout
		if not _active:
			return
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == scene_path:
			break
	_bind_terrain(_find_scene_terrain())


# --- Input handling ---------------------------------------------------------

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _active:
		return AFTER_GUI_INPUT_PASS
	# Drop stale terrain references (scene switched manually).
	if _terrain != null and not is_instance_valid(_terrain):
		_unbind_terrain()
	if _vt == null:
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
					# Shift inverts the mode: paint→erase (carve the solid cell).
					var erase := mb.shift_pressed
					var target: Vector3i = hit.solid if erase else hit.prev
					var value: int = 0 if erase else _current_index
					_paint_with_retry(target, value)
				return AFTER_GUI_INPUT_STOP

			PaintMode.ERASE:
				_current_index = _panel.get_current_index() if _panel else 6
				var hit := _march_to_voxel(camera, mb.position)
				if hit.get("hit", false):
					# Shift inverts the mode: erase→paint (fill the air cell).
					var paint := mb.shift_pressed
					var target: Vector3i = hit.prev if paint else hit.solid
					var value: int = _current_index if paint else 0
					_paint_with_retry(target, value)
				return AFTER_GUI_INPUT_STOP

			PaintMode.FURNITURE:
				if _furniture == null:
					return AFTER_GUI_INPUT_PASS
				var hit := _march_to_voxel(camera, mb.position)
				if hit.get("hit", false):
					if mb.shift_pressed:
						# Shift+LMB: remove furniture. The march samples voxels, not
						# meshes, so clicking a furniture's PreviewMesh keeps going
						# until it hits the solid voxel behind/below it. Furniture is
						# indexed by its footprint air cells (anchor + offsets), so we
						# remove by the air cell in front of the surface — the same
						# cell placement anchors to. hit.solid (the ground block) is
						# never a footprint cell and would always miss.
						if _furniture.remove_at(hit.prev):
							EditorInterface.save_scene()
					else:
						# LMB: place furniture at the air cell in front of surface.
						var def: FurnitureDef = _panel.get_selected_furniture_def() if _panel else null
						if def and _furniture.place(def, hit.prev, _yaw):
							EditorInterface.save_scene()
				return AFTER_GUI_INPUT_STOP

	# Update hover preview ghost on mouse motion.
	var mm := event as InputEventMouseMotion
	if mm != null and _ghost != null:
		_last_camera = camera
		_last_screen_pos = mm.position
		_refresh_ghost(mm.shift_pressed)
	return AFTER_GUI_INPUT_PASS


## Re-run the ghost preview against the last-known camera/pointer, e.g. after
## the yaw changes on R. Pass the current shift state so paint/erase tinting
## stays correct.
func _refresh_ghost(shift: bool) -> void:
	if _ghost == null or _last_camera == null:
		return
	var hit := _march_to_voxel(_last_camera, _last_screen_pos)
	if not hit.get("hit", false):
		_ghost.visible = false
		return
	var mode: int = _panel.get_mode() if _panel else PaintMode.PAINT
	if _panel:
		_brush_radius = _panel.get_brush_radius()
	_ghost.visible = true
	match mode:
		PaintMode.PAINT, PaintMode.ERASE:
			_ghost.mesh = _box_mesh
			_ghost.scale = Vector3(_brush_radius, _brush_radius, _brush_radius)
			# Shift inverts the mode: paint→erase, erase→paint.
			var erase: bool = shift if mode == PaintMode.PAINT else not shift
			var target: Vector3i = hit.solid if erase else hit.prev
			# BoxMesh is centered on its origin; Vector3(target) is the cell corner.
			# Add half a cell so the cube fills the target cell exactly.
			_ghost.global_position = _terrain.to_global(Vector3(target) + Vector3(0.5, 0.5, 0.5))
			if _ghost_mat != null:
				_ghost_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.35) if erase else Color(0.2, 1.0, 0.2, 0.35)

		PaintMode.FURNITURE:
			var def: FurnitureDef = _panel.get_selected_furniture_def() if _panel else null
			if def == null or def.mesh == null:
				_ghost.visible = false
				return
			_ghost.mesh = def.mesh
			_ghost.scale = Vector3.ONE
			var dims := FurnitureLayer.dimensions_of(def)
			var origin := FurnitureLayer.world_origin(hit.prev, dims, _yaw)
			_ghost.global_position = _terrain.to_global(origin)
			_ghost.global_rotation = Vector3(0, deg_to_rad(_yaw * 90), 0)
			if _ghost_mat != null:
				_ghost_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.4)


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
					# Refresh the ghost so the preview reflects the new rotation.
					_refresh_ghost(false)

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
