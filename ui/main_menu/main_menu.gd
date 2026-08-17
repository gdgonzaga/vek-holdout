extends PanelContainer
## Main menu — title screen shown after the splash, and after Quit-to-Main-Menu.
## New Game allocates a fresh save slot and boots into `base_colony`; Load Game
## opens the load_menu screen to pick a slot. Continue (most-recent slot) /
## Settings land here later (GDD §12).

@export var new_game_map_name := "base"

@onready var _new_game_btn: Button = %NewGame
@onready var _load_game_btn: Button = %LoadGame


func _ready() -> void:
	_new_game_btn.pressed.connect(_on_new_game_pressed)
	_load_game_btn.pressed.connect(_on_load_game_pressed)


func _on_new_game_pressed() -> void:
	_start_new_game()


func _on_load_game_pressed() -> void:
	SceneManager.open_screen("load_menu")


## Minimal New Game orchestrator. Allocates a fresh save slot, resets run-scoped
## state, re-seeds defaults via the run_started signal, discovers initial POIs,
## and loads the base colony. Load does NOT go through here — it lives entirely
## inside SaveSystem.load_game (called by a future Load screen), which restores
## POI discovery from save so re-discovery is unnecessary on load.
func _start_new_game() -> void:
	var display_name := "Day 1 — %s" % Time.get_datetime_string_from_system().get_slice(" ", 0)
	SaveSystem.create_save(display_name)
	RunProgress.reset_for_new_game()
	EventBus.run_started.emit()
	# Discover any POI-type maps registered in MapLibrary (relocated verbatim
	# from main.gd, which used to do this unconditionally on boot).
	for def in MapLibrary.get_maps_by_type(MapDef.MapType.POI):
		ExpeditionManager.discover(def.id)
	SceneManager.wipe_map_cache()
	SceneManager.swap_map(new_game_map_name)
	SceneManager.close_screen()
