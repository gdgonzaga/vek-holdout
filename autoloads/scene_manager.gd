extends Node
## Scene swap (base <-> POI) + UI layer management (ARCH lines 81, 235).
##
## STUB: real API surface so other subsystems can call it without crashing, but
## the bodies are TODOs. Owns no UI content (each screen is its own scene).
##
## TODO: implement WorldRoot swap (load base.tscn / poi scenes, transition) and
## layer-20 UI screen management (open_screen/close_screen instance/replace).

const WORLD_SCENE_BASE := "res://voxel/world.tscn"

var _world_root_parent: Node = null    # set by Main; where WorldRoot mounts
var _ui_layer: CanvasLayer = null       # set by Main; the layer-20 slot
var _current_world: Node = null


## Called by Main on startup to give SceneManager the node slots it manages.
func setup(world_parent: Node, ui_layer: CanvasLayer) -> void:
	_world_root_parent = world_parent
	_ui_layer = ui_layer


## Load a WorldRoot scene (base or poi_<id>) under the parent. STUB.
func swap_world(scene_id: String) -> void:
	# TODO: free _current_world, instance the scene for scene_id, add to parent,
	# register with GameState.world_root, then GameState.set_scene_id(scene_id).
	push_warning("SceneManager.swap_world('%s'): not implemented (stub)" % scene_id)


## Open a full-screen UI screen by id in the layer-20 slot. STUB.
func open_screen(screen_id: String) -> void:
	# TODO: instance ui/<screen_id>/<screen_id>.tscn, replace current in _ui_layer.
	push_warning("SceneManager.open_screen('%s'): not implemented (stub)" % screen_id)


## Close the current full-screen UI screen. STUB.
func close_screen() -> void:
	# TODO: free the current screen node in _ui_layer.
	push_warning("SceneManager.close_screen(): not implemented (stub)")
