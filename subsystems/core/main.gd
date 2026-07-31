class_name Main
extends Node
## Root scene — persists across the entire game session (ARCH "Scene Tree", line 59).
## Owns the CanvasLayers, the WorldRoot slot, and the persistent Player. No
## gameplay logic (ARCH line 231).
##
## Structure (built in _ready):
##   Main
##   ├── UILayer (CanvasLayer, layer=20)   full-screen UI slot (SceneManager)
##   ├── HUDLayer (CanvasLayer, layer=10)  HUD slot (mounts hud.tscn later)
##   └── WorldRootSlot (Node)              WorldRoot mounts here (SceneManager)
##
## The Player is created once and persists across world swaps — SceneManager
## reparents it into each loaded world (ARCH: persistent player across scenes).

@onready var _hud_layer: CanvasLayer = $HUDLayer
@onready var _ui_layer: CanvasLayer = $UILayer
@onready var _world_slot: Node = $WorldRootSlot

var _player: Player = null


func _ready() -> void:
	# Hand the node slots to SceneManager so it can swap worlds/screens.
	SceneManager.setup(_world_slot, _ui_layer)
	# Persistent player: created once, reparented into each world on swap.
	_player = preload("res://subsystems/player/player.tscn").instantiate()
	SceneManager.set_player(_player)
	# Throwaway auto-base-load: load the colony on startup so the skeleton has
	# something to show. Move behind the Main Menu (New Game / Continue) when the
	# UI subsystem lands — contradicts boot.gd's "boot -> Main -> Menu" decision.
	SceneManager.swap_world("base_colony")


func _unhandled_input(event: InputEvent) -> void:
	# Pause toggle. UI nodes keep PROCESS_MODE_ALWAYS so the pause menu (when it
	# lands) still works; the WorldRoot + children get disabled by GameState.
	if event.is_action_pressed("ui_cancel"):
		GameState.set_paused(not GameState.paused)
