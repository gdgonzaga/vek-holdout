class_name Main
extends Node
## Root scene — persists across the entire game session (ARCH "Scene Tree", line 59).
## Owns the CanvasLayers, the MapRoot slot, and the persistent Player. No
## gameplay logic (ARCH line 231).
##
## Structure (built in _ready):
##   Main
##   ├── UILayer (CanvasLayer, layer=20)   full-screen UI slot (SceneManager)
##   ├── HUDLayer (CanvasLayer, layer=10)  HUD slot (mounts hud.tscn later)
##   └── MapRootSlot (Node)                 MapRoot mounts here (SceneManager)
##
## The Player is created once and persists across map swaps — SceneManager
## reparents it into each loaded map (ARCH: persistent player across scenes).

@onready var _hud_layer: CanvasLayer = $HUDLayer
@onready var _ui_layer: CanvasLayer = $UILayer
@onready var _map_slot: Node = $MapRootSlot

var _player: Player = null


func _ready() -> void:
	# Hand the node slots to SceneManager so it can swap maps/screens.
	SceneManager.setup(_map_slot, _ui_layer)
	# Persistent player: created once, reparented into each map on swap.
	_player = preload("res://subsystems/player/player.tscn").instantiate()
	SceneManager.set_player(_player)
	# Throwaway auto-base-load: load the colony on startup so the skeleton has
	# something to show. Move behind the Main Menu (New Game / Continue) when the
	# UI subsystem lands — contradicts boot.gd's "boot -> Main -> Menu" decision.
	SceneManager.swap_map("base_colony")
	# Discover any POI-type maps registered in MapLibrary.
	for def in MapLibrary.get_maps_by_type(MapDef.MapType.POI):
		ExpeditionManager.discover(def.id)


func _unhandled_input(event: InputEvent) -> void:
	# Pause toggle. UI nodes keep PROCESS_MODE_ALWAYS so the pause menu (when it
	# lands) still works; the MapRoot + children get disabled by GameState.
	if event.is_action_pressed("ui_cancel"):
		# Close screen if one is open, otherwise toggle pause.
		if SceneManager.is_screen_open():
			SceneManager.close_screen()
			return
		GameState.set_paused(not GameState.paused)
	elif event.is_action_pressed("world_map"):
		if SceneManager.is_screen_open():
			SceneManager.close_screen()
		else:
			SceneManager.open_screen("world_map")
