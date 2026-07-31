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

	# One-frame deferral: child _ready (CameraRig builds its camera) must run
	# before wire_build/wire_player read it. NOT for voxel writes.
	await get_tree().process_frame
	_wire_map(map, map_def)

	GameState.map_root = map
	GameState.set_scene_id(scene_id)
	EventBus.map_loaded.emit(scene_id)


## Wire the instantiated map's subsystems and reparent the player. Extracted
## from the canonical build_test.gd wiring (lines 40-55).
func _wire_map(map: Node, map_def: MapDef) -> void:
	var m: Map = map as Map
	if m == null:
		push_error("SceneManager: scene '%s' root is not a Map" % map_def.scene_path)
		return
	MapWiring.wire_build(m)
	if _player != null:
		var spawns := SpawnHelpers.read_spawns(m)
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


## Open a full-screen UI screen by id in the layer-20 slot. STUB.
func open_screen(screen_id: String) -> void:
	# TODO: instance ui/<screen_id>/<screen_id>.tscn, replace current in _ui_layer.
	push_warning("SceneManager.open_screen('%s'): not implemented (stub)" % screen_id)


## Close the current full-screen UI screen. STUB.
func close_screen() -> void:
	# TODO: free the current screen node in _ui_layer.
	push_warning("SceneManager.close_screen(): not implemented (stub)")
