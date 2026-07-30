class_name Main
extends Node
## Root scene — persists across the entire game session (ARCH "Scene Tree", line 59).
## Owns the CanvasLayers and the WorldRoot slot. Bootstraps structure at startup.
## Does NOT contain gameplay logic (ARCH line 231).
##
## Structure (built in _ready):
##   Main
##   ├── UILayer (CanvasLayer, layer=20)   full-screen UI slot (SceneManager)
##   ├── HUDLayer (CanvasLayer, layer=10)  HUD slot (mounts hud.tscn later)
##   └── WorldRootSlot (Node)              WorldRoot mounts here (SceneManager)

@onready var _hud_layer: CanvasLayer = $HUDLayer
@onready var _ui_layer: CanvasLayer = $UILayer
@onready var _world_slot: Node = $WorldRootSlot


func _ready() -> void:
	# Hand the node slots to SceneManager so it can swap worlds/screens.
	SceneManager.setup(_world_slot, _ui_layer)
	# Load the base WorldRoot on startup (TODO: gate behind New Game / Continue
	# once the Main Menu lands; for now load base directly so the world appears).
	_load_base_world()


func _unhandled_input(event: InputEvent) -> void:
	# Pause toggle. UI nodes keep PROCESS_MODE_ALWAYS so the pause menu (when it
	# lands) still works; the WorldRoot + children get disabled by GameState.
	if event.is_action_pressed("ui_cancel"):
		GameState.set_paused(not GameState.paused)


func _load_base_world() -> void:
	# TODO: replace with SceneManager.swap_world("base") once its body is real.
	# For now, instance world.tscn directly so the skeleton has something to show.
	var world: Node = preload("res://subsystems/voxel/world.tscn").instantiate()
	_world_slot.add_child(world)
	GameState.world_root = world
	GameState.set_scene_id("base")
