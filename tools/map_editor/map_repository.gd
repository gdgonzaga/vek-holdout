class_name MapRepository
extends RefCounted
## Disk repository and filesystem operations for the Map Editor.
##
## Encapsulates all file-system scanning, map scene template stamping, directory
## manipulation, and MapDef resource creation without retaining scene state.

const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")

const MAPS_DIR: String = "res://data/maps/"
const TERRAIN_DIR: String = "res://data/terrain/"
const TEMPLATE_PATH: String = "res://subsystems/maps/map_template.tscn"


# =================
# Primary Functions
# =================

## Scans the maps directory and returns all valid MapDef resources found.
static func scan_maps() -> Array[MapDef]:
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


## Shared-def scan for the launcher's noise dropdown: <dir_path>/*.tres minus
## heightmap-driven defs (those are per-map content, not shared baselines).
## `dir_path` defaults to the shipped TERRAIN_DIR so every production caller is
## unaffected; tests pass a synthetic user:// directory to stay content-agnostic.
static func scan_noise_defs(dir_path: String = TERRAIN_DIR) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return results
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.ends_with(".tres"):
			var path := dir_path + entry
			var terrain_def := load(path) as TerrainGenDef
			if terrain_def != null and terrain_def.heightmap == null:
				var def_id := terrain_def.id if not terrain_def.id.is_empty() else entry.get_basename()
				results.append({"id": def_id, "path": path})
		entry = dir.get_next()
	dir.list_dir_end()
	results.sort_custom(func(a: Dictionary, b: Dictionary): return a["id"] < b["id"])
	return results


## Validates and writes all disk files for a new map (folder, scene, map_def, and terrain_gen).
## Returns the path to the newly stamped scene file, or empty string on failure.
static func create_map_files(payload: Dictionary, config: MapEditorConfig) -> String:
	var map_name := payload.get("map_id", "") as String
	# 1. Validation: verify that map_name satisfies naming rules.
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
	# 2. Template scene stamping: clone the template scene with the per-map database path.
	_stamp_map_scene(TEMPLATE_PATH, tscn_path, db_path)
	# 3. Resource initialization: construct and persist MapDef and its owned terrain resources.
	_create_map_def(payload, folder_path, tscn_path, config)

	return tscn_path


## Removes the map directory and all its contents from disk. Returns false
## (with push_error) if the directory could not be found or cleaned up.
static func delete_map(map_id: String) -> bool:
	var dir_path := MAPS_DIR + map_id + "/"
	if not DirAccess.dir_exists_absolute(dir_path):
		push_error("MapEditor: cannot delete map '%s' — directory not found" % map_id)
		return false
	# 1. Directory Cleanup: recursively remove all files and directories in map folder.
	return _remove_dir_recursive(dir_path)


# ===================
# Auxiliary Functions
# ===================

static func _stamp_map_scene(template_path: String, tscn_dest_path: String, db_dest_path: String) -> void:
	## Auxiliary: Clones the map template scene and binds the per-map SQLite stream path.
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


static func _create_map_def(payload: Dictionary, folder_path: String, tscn_path: String, config: MapEditorConfig) -> void:
	## Auxiliary: Assembles and persists the MapDef resource and any owned terrain generator.
	var map_name := payload.get("map_id", "") as String
	# 1. Shell definition: populate map shell metadata, bounds, and initial properties.
	var def := _new_map_def_shell(payload, tscn_path, config)
	# 2. Initial terrain definition: construct per-map owned terrain generator resource.
	def.terrain_gen = _build_initial_terrain_def(payload, map_name, config)
	# 3. Water configuration: synchronize water parameters between MapDef and terrain generator.
	def.water_enabled = bool(payload.get("water_enabled", false))
	def.water_level = float(payload.get("water_level", -2.0))
	MapTerrainAuthoring.apply_water(def.terrain_gen, def.water_enabled, def.water_level)
	# 4. Persistence: persist the owned terrain def so MapDef stores its relative path.
	MapTerrainAuthoring.persist_owned(def.terrain_gen, MAPS_DIR, map_name)
	var err := ResourceSaver.save(def, folder_path + "map_def.tres")
	if err != OK:
		push_error("MapEditor: failed to save MapDef to '%s' (error %d)" % [folder_path + "map_def.tres", err])


static func _new_map_def_shell(payload: Dictionary, tscn_path: String, config: MapEditorConfig) -> MapDef:
	## Auxiliary: Instantiates a fresh MapDef shell with properties mapped from the creation payload.
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
	# 1. Flora parameters: apply flora spawn parameters and default palette from config.
	_apply_flora_payload(def, payload, config)
	return def


static func _apply_flora_payload(def: MapDef, payload: Dictionary, config: MapEditorConfig) -> void:
	## Auxiliary: Maps flora configuration fields from payload and editor config to the MapDef.
	def.flora_spawns_per_day = int(payload.get("flora_spawns_per_day", 0))
	def.flora_spawn_cap = int(payload.get("flora_spawn_cap", 60))
	def.flora_max_spawn_attempts = int(payload.get("flora_max_spawn_attempts", 15))
	if config != null and not config.default_flora_palette.is_empty():
		def.flora_palette = config.default_flora_palette.duplicate()


static func _build_initial_terrain_def(payload: Dictionary, map_name: String, config: MapEditorConfig) -> TerrainGenDef:
	## Auxiliary: Resolves terrain generation def based on launcher terrain mode.
	match int(payload.get("terrain_mode", EditorLauncherClass.TerrainMode.NOISE)):
		EditorLauncherClass.TerrainMode.NONE:
			return null
		EditorLauncherClass.TerrainMode.HEIGHTMAP:
			# 1. Heightmap generation: build a per-map heightmap TerrainGenDef with embedded texture.
			return _initial_heightmap_def(payload, map_name)
		_:
			# 2. Noise generation: duplicate or configure default noise def for the map.
			return _initial_noise_def(payload, map_name, config)


static func _initial_heightmap_def(payload: Dictionary, map_name: String) -> TerrainGenDef:
	## Auxiliary: Builds a per-map heightmap TerrainGenDef from payload image data.
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


static func _initial_noise_def(payload: Dictionary, map_name: String, config: MapEditorConfig) -> TerrainGenDef:
	## Auxiliary: Resolves a map-owned copy of the noise TerrainGenDef to protect shared baselines.
	var noise_path := payload.get("noise_def_path", "") as String
	var shared: TerrainGenDef = null
	if ResourceLoader.exists(noise_path):
		shared = load(noise_path) as TerrainGenDef
	elif config != null:
		shared = config.default_noise_def
	return MapTerrainAuthoring.ensure_map_owned(shared, map_name)


static func _remove_dir_recursive(dir_path: String) -> bool:
	## Auxiliary: Traverses a directory tree and deletes all files and nested folders.
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("MapEditor: failed to open directory '%s'" % dir_path)
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full_path := dir_path.path_join(entry)
		if dir.current_is_dir():
			# 1. Recursive cleanup: remove sub-directories first.
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
