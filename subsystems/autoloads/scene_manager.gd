extends Node
## Scene swap (base <-> POI) + UI layer management (ARCH lines 81, 235).
##
## swap_map() is the single entry point for loading any map — base startup and
## POI travel both go here. It looks up the MapDef in MapLibrary, frees the
## current map, instances the new one, and wires subsystems via MapWiring.
## Emits the map_loading/loaded/unloading signals so HUD/save/ExpeditionManager
## can hook in.

var _map_root_parent: Node = null    # set by Main; where MapRoot mounts
var _ui_layer: CanvasLayer = null      # set by Main; the layer-20 slot
var _current_map: Node = null
var _current_scene_id: String = ""
var _current_screen: Node = null       # currently open full-screen UI
var _player: Player = null


## Called by Main on startup to give SceneManager the node slots it manages.
func setup(map_parent: Node, ui_layer: CanvasLayer) -> void:
	_map_root_parent = map_parent
	_ui_layer = ui_layer


## Register the persistent player used across swaps. Reparented into each map
## by _wire_map.
func set_player(player: Player) -> void:
	_player = player


func get_current_scene_id() -> String:
	return _current_scene_id


## The currently-loaded Map root, or null. Used by SaveSystem to park the live
## map's state on swap and serialize its layers on save.
func get_current_map() -> Node:
	return _current_map


## The persistent Player (reparented into each map by _wire_map), or null.
## Used by SaveSystem to serialize/restore player state.
func get_player() -> Player:
	return _player


## Load a MapRoot scene (base or poi_<id>) under the parent. The single swap
## point: base startup and POI travel both call this.
func swap_map(scene_id: String) -> void:
	var map_def: MapDef = MapLibrary.get_def(scene_id)
	if map_def == null:
		push_error("SceneManager: unknown map '%s'" % scene_id)
		return

	EventBus.map_loading.emit(scene_id)

	if _current_map != null:
		EventBus.map_unloading.emit(_current_scene_id)
		_current_map.queue_free()
		_current_map = null
		_current_scene_id = ""

	var map: Node = load(map_def.scene_path).instantiate()
	_map_root_parent.add_child(map)
	_current_map = map
	_current_scene_id = scene_id

	# Copy-on-load: if the map has a SQLite stream with a res:// database, copy
	# the pristine .sqlite to user://maps/<id>/ and redirect the stream path.
	# This keeps authored maps untouched while allowing runtime mutations.
	_redirect_sqlite_stream(map, map_def.id)

	# One-frame deferral: child _ready (CameraRig builds its camera) must run
	# before wire_build/wire_player read it. NOT for voxel writes.
	await get_tree().process_frame
	_wire_map(map, map_def)

	GameState.map_root = map
	GameState.set_scene_id(scene_id)
	EventBus.map_loaded.emit(scene_id)


## Free the current map without loading a replacement. Used by Quit-to-Main-
## Menu so the simulation isn't running under the title screen. Emits
## map_unloading first so SaveSystem can park the outgoing state (harmless if
## the player then loads a different slot — load_game replaces _parked). The
## persistent Player is reparented out before the free so it survives for the
## next run (it was created once in main.gd and must never be freed with a map).
func unload_current_map() -> void:
	if _current_map == null:
		return
	EventBus.map_unloading.emit(_current_scene_id)
	# Drop the player's interactable target BEFORE freeing the map — the target
	# is a child of the map and would be freed with it, leaving the HUD's
	# InteractLabel showing stale text over the title screen.
	if _player != null and is_instance_valid(_player):
		_player.clear_interactable()
	if _player != null and is_instance_valid(_player) and _player.get_parent() == _current_map:
		_current_map.remove_child(_player)
	_current_map.queue_free()
	_current_map = null
	_current_scene_id = ""
	GameState.map_root = null
	GameState.set_scene_id("")


## Wipe the user://maps/ cache so the next swap_map(s) pull fresh copies
## from res://. Called at New Game start so authored edits are always picked up.
## POI round-trips within a session still preserve runtime changes because this
## only runs once (at New Game, not on every swap).
func wipe_map_cache() -> void:
	var maps_dir := DirAccess.open("user://maps/")
	if maps_dir == null:
		return
	# Collect subdirectories first so we don't mutate the listing while iterating.
	var subdirs: Array[String] = []
	maps_dir.list_dir_begin()
	var name := maps_dir.get_next()
	while name != "":
		if maps_dir.current_is_dir() and not name.begins_with("."):
			subdirs.append(name)
		name = maps_dir.get_next()
	maps_dir.list_dir_end()
	# Delete each map subdirectory recursively.
	for subdir in subdirs:
		_remove_recursive("user://maps/" + subdir)
	# Remove the now-empty parent (harmless if not empty).
	DirAccess.remove_absolute("user://maps/")


## Recursively remove a directory tree under user://.
func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path + "/" + entry
		if dir.current_is_dir():
			_remove_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


## If the map's VoxelTerrain uses a VoxelStreamSQLite backed by a res:// path,
## copy the pristine database to user://maps/<map_id>/ and redirect the stream.
## If the terrain has no stream, inject one pointing at user://maps/<map_id>/.
## This keeps authored maps untouched while allowing runtime mutations.
func _redirect_sqlite_stream(map: Node, map_id: String) -> void:
	var m: Map = map as Map
	if m == null:
		return
	var terrain := m.get_blocky_terrain()
	if terrain == null:
		return
	# Ensure the runtime directory exists.
	var runtime_dir := "user://maps/%s/" % map_id
	var runtime_path := runtime_dir + "map.sqlite"
	DirAccess.make_dir_recursive_absolute(runtime_dir.trim_suffix("/"))

	if terrain.stream is VoxelStreamSQLite:
		var stream: VoxelStreamSQLite = terrain.stream
		var src_path: String = stream.database_path
		# Only copy res:// sources — user:// is already a runtime copy.
		if src_path.begins_with("res://"):
			if not FileAccess.file_exists(runtime_path) and FileAccess.file_exists(src_path):
				var err := DirAccess.copy_absolute(src_path, runtime_path)
				if err != OK:
					push_error("SceneManager: failed to copy '%s' -> '%s' (error %d)" \
							% [src_path, runtime_path, err])
					return
		stream.database_path = runtime_path
	elif terrain.stream == null:
		# Template-based map with no baked stream: inject one at runtime.
		var stream := VoxelStreamSQLite.new()
		stream.database_path = runtime_path
		terrain.stream = stream


## Wire the instantiated map's subsystems and reparent the player. Extracted
## from the canonical build_test.gd wiring (lines 40-55).
func _wire_map(map: Node, map_def: MapDef) -> void:
	var m: Map = map as Map
	if m == null:
		push_error("SceneManager: scene '%s' root is not a Map" % map_def.scene_path)
		return
	var furniture_layer: FurnitureLayer = MapWiring.wire_build(m)

	# Read spawns once — used for both furniture replay and player positioning.
	var spawns: Dictionary = SpawnHelpers.read_spawns(m)

	# Replay authored furniture markers into the live FurnitureLayer — UNLESS
	# SaveSystem is restoring a saved/parked state for this map, in which case
	# the parked state owns the furniture set (applying authored markers too
	# would double-spawn every piece).
	if furniture_layer != null:
		if SaveSystem.apply_parked_state_if_any(map_def.id, m):
			pass  # parked state applied; skip authored replay
		else:
			for rec in spawns.get("furniture", []):
				var def := BuildLibrary.get_def(rec["def_id"])
				if def == null:
					push_warning("SceneManager: furniture def '%s' not in catalog" % rec["def_id"])
					continue
				furniture_layer.spawn(def, rec["anchor"], rec["yaw"])
			# The markers carry an editor-only PreviewMesh that would duplicate the
			# spawned mesh and survive deconstruct; now that they're replayed, drop them.
			SpawnHelpers.clear_furniture_markers(m)

	if _player != null:
		var spawn_pos: Vector3 = spawns.player if spawns.player != Vector3.ZERO else map_def.player_spawn
		# Reparent into the map BEFORE setting position — global_position
		# requires the node to be inside the tree to resolve.
		if _player.get_parent() != m:
			var old_parent := _player.get_parent()
			if old_parent != null:
				old_parent.remove_child(_player)
			m.add_child(_player)
		_player.global_position = spawn_pos
		MapWiring.wire_player(m, _player)
	# Colonist spawn/reparent into the map's ColonistContainer (Phase 2). No-op for
	# maps with no container, or no ColonistSpawn markers + an empty roster.
	MapWiring.wire_colonists(m)


## Open a full-screen UI screen by id in the layer-20 slot.
## Closes any currently open screen first.
func open_screen(screen_id: String) -> void:
	close_screen()
	var scene_path := "res://ui/%s/%s.tscn" % [screen_id, screen_id]
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("SceneManager: failed to load screen '%s' from '%s'" % [screen_id, scene_path])
		return
	var screen: Node = scene.instantiate()
	_ui_layer.add_child(screen)
	_current_screen = screen
	UiGate.open_modal(screen)


## Close the current full-screen UI screen, if any.
func close_screen() -> void:
	if _current_screen != null:
		UiGate.close_modal(_current_screen)
		_current_screen.queue_free()
		_current_screen = null


## Returns true if a full-screen UI screen is currently open.
func is_screen_open() -> bool:
	return _current_screen != null
