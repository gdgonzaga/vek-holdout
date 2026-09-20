extends GdUnitTestSuite

## HUD wiring of the inventory panel: the HUD hands the player to the panel, and the
## panel (not the HUD) owns the I / Esc hotkeys and the no-stacking rule.

const PlayerScene = preload("res://subsystems/player/player.tscn")
const HudScene = preload("res://ui/hud/hud.tscn")

var _other_modal: Node = null


func after_test() -> void:
	# Leave the global UiGate clean for whichever suite runs next.
	if is_instance_valid(_other_modal):
		UiGate.close_modal(_other_modal)
	_other_modal = null


func _make_hud() -> Control:
	var player: Player = PlayerScene.instantiate()
	auto_free(player)
	add_child(player)
	var hud := auto_free(HudScene.instantiate()) as Control
	add_child(hud)
	hud.setup(player)
	return hud


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame


func test_hud_mounts_the_inventory_panel_closed() -> void:
	var hud := _make_hud()
	var panel := hud.get_node("InventoryPanel") as InventoryPanel
	assert_object(panel).is_not_null()
	assert_bool(panel.is_open()).is_false()
	assert_bool(panel.visible).is_false()


func test_inventory_key_opens_then_closes_the_panel() -> void:
	var hud := _make_hud()
	var panel := hud.get_node("InventoryPanel") as InventoryPanel

	await _press("inventory_toggle")
	assert_bool(panel.is_open()).is_true()

	await _press("inventory_toggle")
	assert_bool(panel.is_open()).is_false()


func test_cancel_key_closes_the_open_panel() -> void:
	var hud := _make_hud()
	var panel := hud.get_node("InventoryPanel") as InventoryPanel
	panel.open()

	await _press("ui_cancel")

	assert_bool(panel.is_open()).is_false()


func test_inventory_key_never_opens_over_another_modal() -> void:
	# Break caught: dropping the UiGate check would stack the inventory on top of a storage panel.
	var hud := _make_hud()
	var panel := hud.get_node("InventoryPanel") as InventoryPanel
	_other_modal = auto_free(Node.new())
	add_child(_other_modal)
	UiGate.open_modal(_other_modal)

	await _press("inventory_toggle")

	assert_bool(panel.is_open()).is_false()
