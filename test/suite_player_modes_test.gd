extends GdUnitTestSuite

## Player mode transitions for the tool modes (build placement, dig box, area
## designation, harvest box): Esc leaves any of them for Normal, the toggle hotkeys
## enter and leave their own mode only from Normal, and each transition is announced
## on the mode's EventBus toggled signal. Menu modes own their own Esc.

const PlayerScene = preload("res://subsystems/player/player.tscn")

## CanvasLayers already at the fallback mount point before a test, so after_test can free any
## fallback layer the player created there (it would otherwise outlive the test).
var _scene_layers_before: Array[Node] = []


## Records the bool payload of a toggled signal. A RefCounted receiver, so the
## connection to the EventBus autoload dies with the log instead of leaking into
## later suites.
class ToggleLog extends RefCounted:
	var values: Array[bool] = []

	func _init(toggled: Signal) -> void:
		toggled.connect(_on_toggled)

	func _on_toggled(active: bool) -> void:
		values.append(active)


func before_test() -> void:
	_scene_layers_before = _canvas_layers_at_mount()


func after_test() -> void:
	for layer: Node in _canvas_layers_at_mount():
		if not _scene_layers_before.has(layer):
			layer.free()


func test_ui_cancel_leaves_each_tool_mode_and_announces_it() -> void:
	# Break caught: a tool mode missing from the Esc handling leaves the player stuck in it,
	# or leaves the controllers listening for the toggled(false) that never comes.
	var tool_modes: Array = [
		[Player.Mode.BUILD_PLACEMENT, EventBus.build_placement_toggled],
		[Player.Mode.DIG_BOX_DESIGNATION, EventBus.dig_box_toggled],
		[Player.Mode.AREA_DESIGNATION, EventBus.area_designation_toggled],
		[Player.Mode.HARVEST_BOX_DESIGNATION, EventBus.harvest_box_toggled],
	]
	for entry: Array in tool_modes:
		var player := _spawn_player()
		player.mode = entry[0]
		var log := ToggleLog.new(entry[1])

		player.get_node("InputComponent").ui_cancel_pressed.emit()

		assert_int(player.mode).is_equal(Player.Mode.NORMAL)
		assert_array(log.values).is_equal([false])


func test_ui_cancel_in_a_tool_mode_marks_the_press_handled() -> void:
	# Break caught: Main treats the same Esc press as "open pause menu" on top of leaving the mode.
	var player := _spawn_player()
	player.mode = Player.Mode.DIG_BOX_DESIGNATION

	player.get_node("InputComponent").ui_cancel_pressed.emit()

	assert_bool(get_viewport().is_input_handled()).is_true()


func test_ui_cancel_ignores_modes_that_are_not_tool_modes() -> void:
	# Break caught: Esc closing the wrong thing. Normal has nothing to leave, and the menus
	# handle their own Esc, so the press must stay unhandled for Main's pause menu.
	var all_toggles := [
		ToggleLog.new(EventBus.build_placement_toggled),
		ToggleLog.new(EventBus.dig_box_toggled),
		ToggleLog.new(EventBus.area_designation_toggled),
		ToggleLog.new(EventBus.harvest_box_toggled),
	]
	for other_mode: Player.Mode in [Player.Mode.NORMAL, Player.Mode.BUILD_MENU, Player.Mode.DESIGNATION_MENU]:
		var player := _spawn_player()
		player.mode = other_mode

		player.get_node("InputComponent").ui_cancel_pressed.emit()

		assert_int(player.mode).is_equal(other_mode)
	for toggle_log: ToggleLog in all_toggles:
		assert_array(toggle_log.values).is_empty()


func test_dig_box_hotkey_enters_then_leaves_its_mode() -> void:
	# Break caught: the second press not toggling back out, or a missing toggled announcement.
	var player := _spawn_player()
	var log := ToggleLog.new(EventBus.dig_box_toggled)
	var hotkey: Signal = player.get_node("InputComponent").dig_box_toggle_pressed

	hotkey.emit()
	assert_int(player.mode).is_equal(Player.Mode.DIG_BOX_DESIGNATION)

	hotkey.emit()
	assert_int(player.mode).is_equal(Player.Mode.NORMAL)
	assert_array(log.values).is_equal([true, false])


func test_harvest_box_hotkey_enters_then_leaves_its_mode() -> void:
	# Break caught: same toggle contract as the dig box, on its own mode and signal.
	var player := _spawn_player()
	var log := ToggleLog.new(EventBus.harvest_box_toggled)
	var hotkey: Signal = player.get_node("InputComponent").harvest_box_toggle_pressed

	hotkey.emit()
	assert_int(player.mode).is_equal(Player.Mode.HARVEST_BOX_DESIGNATION)

	hotkey.emit()
	assert_int(player.mode).is_equal(Player.Mode.NORMAL)
	assert_array(log.values).is_equal([true, false])


func test_toggle_hotkey_is_ignored_inside_another_tool_mode() -> void:
	# Break caught: a toggle stacking a second tool mode over the active one (no stacking).
	var player := _spawn_player()
	player.mode = Player.Mode.HARVEST_BOX_DESIGNATION
	var dig_log := ToggleLog.new(EventBus.dig_box_toggled)

	player.get_node("InputComponent").dig_box_toggle_pressed.emit()

	assert_int(player.mode).is_equal(Player.Mode.HARVEST_BOX_DESIGNATION)
	assert_array(dig_log.values).is_empty()


func test_toggle_hotkey_is_ignored_while_the_player_is_busy() -> void:
	# Break caught: a held player (timed action) entering a designation mode.
	var player := _spawn_player()
	player.set_busy(true)
	var log := ToggleLog.new(EventBus.harvest_box_toggled)

	player.get_node("InputComponent").harvest_box_toggle_pressed.emit()

	assert_int(player.mode).is_equal(Player.Mode.NORMAL)
	assert_array(log.values).is_empty()


func test_buildable_selection_enters_build_placement_and_announces_it() -> void:
	# Break caught: the menu closing without the player flipping to placement, or the
	# BuildController never hearing build_placement_toggled(true).
	var player := _spawn_player()
	var placement_log := ToggleLog.new(EventBus.build_placement_toggled)

	EventBus.buildable_selected.emit("test_buildable")

	assert_int(player.mode).is_equal(Player.Mode.BUILD_PLACEMENT)
	assert_array(placement_log.values).is_equal([true])


func test_menus_opened_without_any_menu_layer_share_one_fallback_layer() -> void:
	# Break caught: the fallback CanvasLayer never joining the layer group the lookup reads, so every
	# menu open builds another layer under the scene (never reused, never freed) when none exists.
	var player := _spawn_player()

	player.open_build_menu()
	var first_layer := player._build_menu.get_parent()
	player._build_menu.close()
	player.open_build_menu()

	assert_object(player._build_menu.get_parent()).is_same(first_layer)


func test_menus_mount_on_the_hud_layer_when_both_layers_exist() -> void:
	# Break caught: modal menus landing in the UILayer, which is SceneManager's full-screen slot
	# (AGENTS.md: ad-hoc panels mount on the CanvasLayer in group "hud_layer").
	var hud_layer := _mount_layer("hud_layer")
	_mount_layer("ui_layer")
	var player := _spawn_player()

	player.open_build_menu()

	assert_object(player._build_menu.get_parent()).is_same(hud_layer)


func test_menus_fall_back_to_the_ui_layer_when_there_is_no_hud_layer() -> void:
	# Break caught: scenes that only have a UILayer losing their menus entirely.
	var ui_layer := _mount_layer("ui_layer")
	var player := _spawn_player()

	player.open_build_menu()

	assert_object(player._build_menu.get_parent()).is_same(ui_layer)


func test_area_designation_hotkey_in_that_mode_reopens_the_designation_menu() -> void:
	# Break caught: leaving area designation without announcing it (the controller stays armed),
	# or without returning to the menu for a quick tool swap.
	_mount_ui_layer()
	var player := _spawn_player()
	player.mode = Player.Mode.AREA_DESIGNATION
	var log := ToggleLog.new(EventBus.area_designation_toggled)

	player.get_node("InputComponent").area_designation_toggle_pressed.emit()

	assert_array(log.values).is_equal([false])
	assert_int(player.mode).is_equal(Player.Mode.DESIGNATION_MENU)


# --- Fixtures ----------------------------------------------------------------

## Auxiliary: Instantiates player.tscn into the test tree.
func _spawn_player() -> Player:
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	return player


## Auxiliary: Every CanvasLayer that is a direct child of the node the player mounts a fallback
## UI layer on: the running scene, or the tree root when no scene is set (as under the test runner).
func _canvas_layers_at_mount() -> Array[Node]:
	var layers: Array[Node] = []
	var tree := get_tree()
	var mount: Node = tree.current_scene if tree.current_scene != null else tree.root
	for child in mount.get_children():
		if child is CanvasLayer:
			layers.append(child)
	return layers


## Auxiliary: A CanvasLayer in `group_name` owned by the test, so menus the player mounts are
## freed with it instead of leaking modal state into later suites.
func _mount_layer(group_name: String) -> CanvasLayer:
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	layer.add_to_group(group_name)
	add_child(layer)
	return layer


## Auxiliary: A "ui_layer" CanvasLayer owned by the test.
func _mount_ui_layer() -> void:
	_mount_layer("ui_layer")
