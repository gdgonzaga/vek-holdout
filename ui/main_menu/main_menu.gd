extends PanelContainer
## Main menu — title screen shown after the splash. Minimal for now: a single
## "New Game" button that boots into `base_colony`. Continue / Load / Settings /
## Quit land here later (GDD §12).
##
## Opened via SceneManager.open_screen("main_menu") from the splash (or, later,
## from Quit-to-Main-Menu). No save slot is created — SaveSystem is a stub, so
## New Game just resets run state and loads the base map.

@onready var _new_game_btn: Button = %NewGame


func _ready() -> void:
	_new_game_btn.pressed.connect(_on_new_game_pressed)


func _on_new_game_pressed() -> void:
	_start_new_game()


## Minimal New Game orchestrator. Resets run-scoped state, re-seeds defaults via
## the run_started signal, discovers initial POIs, and loads the base colony.
##
## `set_save_slot` is deliberately skipped — SaveSystem is stubbed. When
## Continue/Load land, lift this into a small autoload (or the SaveSystem) so
## both New Game and Load share a single "enter run" path.
func _start_new_game() -> void:
	RunProgress.reset_for_new_game()
	EventBus.run_started.emit()
	# Discover any POI-type maps registered in MapLibrary (relocated verbatim
	# from main.gd, which used to do this unconditionally on boot).
	for def in MapLibrary.get_maps_by_type(MapDef.MapType.POI):
		ExpeditionManager.discover(def.id)
	SceneManager.swap_map("base_colony")
	SceneManager.close_screen()
