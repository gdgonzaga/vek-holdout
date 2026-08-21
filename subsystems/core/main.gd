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
	# Mount the persistent HUD on the HUDLayer.
	var hud: Control = preload("res://ui/hud/hud.tscn").instantiate()
	_hud_layer.add_child(hud)
	hud.setup(_player)
	# Mount the persistent game-log tail on the HUDLayer.
	var log_feed: Control = preload("res://ui/log_feed/log_feed.tscn").instantiate()
	_hud_layer.add_child(log_feed)
	# Mount the persistent dig box HUD overlay on the HUDLayer.
	var dig_box_hud: Control = preload("res://ui/dig_box_hud/dig_box_hud.tscn").instantiate()
	_hud_layer.add_child(dig_box_hud)
	# No map is loaded here — the Main Menu's New Game button drives the base
	# load (see ui/main_menu/main_menu.gd). base_colony + POI discovery moved
	# behind the menu so the menu gates gameplay.


func _unhandled_input(event: InputEvent) -> void:
	# Esc: close whatever screen is open (pause menu, world map, log history);
	# otherwise, if a modal panel is open it owns that Esc and closes itself;
	# only a clean game state opens the pause menu. M/H toggle their screens
	# but never open one on top of an open panel — UiGate prevents stacking.
	if event.is_action_pressed("ui_cancel"):
		if SceneManager.is_screen_open():
			SceneManager.close_screen()
			return
		if not UiGate.is_input_blocked():
			SceneManager.open_screen("pause_menu")
	elif event.is_action_pressed("world_map"):
		if SceneManager.is_screen_open():
			SceneManager.close_screen()
		elif not UiGate.is_input_blocked():
			SceneManager.open_screen("world_map")
	elif event.is_action_pressed("log_history"):
		if SceneManager.is_screen_open():
			SceneManager.close_screen()
		elif not UiGate.is_input_blocked():
			SceneManager.open_screen("log_history")
	elif event.is_action_pressed("colony_management"):
		if SceneManager.is_screen_open():
			SceneManager.close_screen()
		elif not UiGate.is_input_blocked():
			SceneManager.open_screen("colony_management")
