extends GdUnitTestSuite

## Player inventory panel (ui/inventory/inventory_panel): carried stacks, the
## Equipped strip that replaced the per-row Equipped toggle, and their actions.
## Content-agnostic: in-memory ItemDefs registered in ItemDB for the test only.

const PlayerScene = preload("res://subsystems/player/player.tscn")
const _PanelScene: PackedScene = preload("res://ui/inventory/inventory_panel.tscn")
const ItemsLayerFixture = preload("res://test/helpers/items_layer_fixture.gd")

var _previous_defs: Dictionary = {}
var _panel: InventoryPanel = null


func before_test() -> void:
	# Drop buttons spawn WorldItems, which need a map ItemsLayer to land in.
	ItemsLayerFixture.add_to(self)


func after_test() -> void:
	# A panel left open would keep the global UiGate blocking input for later suites.
	if is_instance_valid(_panel) and _panel.is_open():
		_panel.close()
	_panel = null
	for item_id: String in _previous_defs:
		if _previous_defs[item_id] != null:
			ItemDB._defs_by_id[item_id] = _previous_defs[item_id]
		else:
			ItemDB._defs_by_id.erase(item_id)
	_previous_defs.clear()


func _register_item(item_id: String, tags: Array[String], weight: float = 1.0) -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = item_id
	def.tags = tags
	def.weight = weight
	if not _previous_defs.has(item_id):
		_previous_defs[item_id] = ItemDB._defs_by_id.get(item_id, null)
	ItemDB._defs_by_id[item_id] = def
	return def


## A player plus a panel wired to it (panel not yet opened).
func _make_panel() -> Player:
	var player: Player = PlayerScene.instantiate()
	auto_free(player)
	add_child(player)
	_panel = auto_free(_PanelScene.instantiate()) as InventoryPanel
	add_child(_panel)
	_panel.setup(player)
	return player


func _item_rows() -> Array[Node]:
	return _panel.get_node("%ItemList").get_children()


func _equipped_rows() -> Array[Node]:
	return _panel.get_node("%EquippedList").get_children()


## The WorldItem matching item_id among every ground item in the tree (drop tests spawn theirs
## under the fixture ItemsLayer via Player.drop_item -> WorldItem.spawn_at), or null if none.
func _find_world_item(item_id: String) -> WorldItem:
	for node: Node in get_tree().get_nodes_in_group("world_items"):
		var item := node as WorldItem
		if item != null and item.item_id == item_id:
			return item
	return null


func test_open_lists_each_carried_stack() -> void:
	var player := _make_panel()
	_register_item("test_panel_wood", ["material"], 2.0)
	_register_item("test_panel_stone", ["material"], 5.0)
	player.inventory.add("test_panel_wood", 3)
	player.inventory.add("test_panel_stone", 1)

	_panel.open()

	assert_int(_item_rows().size()).is_equal(2)


func test_open_shows_carry_weight_against_capacity() -> void:
	var player := _make_panel()
	_register_item("test_panel_wood", ["material"], 2.0)
	player.inventory.add("test_panel_wood", 3)

	_panel.open()

	var expected := "%.1f / %.0f" % [6.0, player.inventory.capacity]
	assert_str((_panel.get_node("%WeightLabel") as Label).text).is_equal(expected)


func test_closed_panel_does_not_rebuild_on_inventory_changes() -> void:
	# Break caught: refreshing while hidden rebuilds every row on every pickup for nothing.
	var player := _make_panel()
	_register_item("test_panel_wood", ["material"])
	player.inventory.add("test_panel_wood", 1)
	await get_tree().process_frame

	assert_int(_item_rows().size()).is_equal(0)

	_panel.open()
	assert_int(_item_rows().size()).is_equal(1)


func test_equipped_item_shows_in_the_strip_and_not_in_the_carried_list() -> void:
	var player := _make_panel()
	var axe := _register_item("test_panel_axe", ["tool"])
	player.inventory.add("test_panel_axe", 1)
	player.equip_item(axe)

	_panel.open()

	assert_int(_equipped_rows().size()).is_equal(1)
	assert_int(_item_rows().size()).is_equal(0)


func test_equipped_strip_shows_a_placeholder_when_nothing_is_equipped() -> void:
	_make_panel()

	_panel.open()

	assert_int(_equipped_rows().size()).is_equal(0)
	assert_bool((_panel.get_node("%EquippedEmptyLabel") as Control).visible).is_true()


func test_equipped_placeholder_hides_once_something_is_equipped() -> void:
	var player := _make_panel()
	var axe := _register_item("test_panel_axe", ["tool"])
	player.inventory.add("test_panel_axe", 1)
	player.equip_item(axe)

	_panel.open()

	assert_bool((_panel.get_node("%EquippedEmptyLabel") as Control).visible).is_false()


func test_unequip_row_returns_the_item_and_refreshes_both_lists() -> void:
	var player := _make_panel()
	var axe := _register_item("test_panel_axe", ["tool"])
	player.inventory.add("test_panel_axe", 1)
	player.equip_item(axe)
	_panel.open()

	(_equipped_rows()[0] as EquippedSlotRow).unequip_pressed.emit(Equipment.SLOT_MAIN_HAND)
	await get_tree().process_frame

	assert_int(_equipped_rows().size()).is_equal(0)
	assert_int(_item_rows().size()).is_equal(1)
	assert_int(player.inventory.get_item_count("test_panel_axe")).is_equal(1)


func test_unequip_into_a_full_pack_explains_why_nothing_happened() -> void:
	var player := _make_panel()
	var axe := _register_item("test_panel_axe", ["tool"], 5.0)
	var filler := _register_item("test_panel_filler", ["material"])
	player.inventory.add("test_panel_axe", 1)
	player.equip_item(axe)
	player.inventory.add("test_panel_filler", int(player.inventory.capacity))
	_panel.open()

	(_equipped_rows()[0] as EquippedSlotRow).unequip_pressed.emit(Equipment.SLOT_MAIN_HAND)

	var status := _panel.get_node("%StatusLabel") as Label
	assert_bool(status.visible).is_true()
	assert_str(status.text).contains("room")
	assert_str(player.get_equipped_item().id).is_equal("test_panel_axe")
	assert_object(filler).is_not_null()


func test_equip_action_is_offered_only_for_items_that_have_a_slot() -> void:
	var player := _make_panel()
	_register_item("test_panel_axe", ["tool"])
	_register_item("test_panel_rock", ["material"])
	player.inventory.add("test_panel_axe", 1)
	player.inventory.add("test_panel_rock", 1)

	_panel.open()

	var offered: Array[bool] = []
	for row: Node in _item_rows():
		offered.append((row.get_node("%EquipButton") as Button).visible)
	offered.sort()
	assert_array(offered).is_equal([false, true])


func test_equip_action_is_offered_for_wearable_apparel() -> void:
	# Break caught: gating on ItemDef.is_equippable() hides Equip for apparel the player could wear.
	var player := _make_panel()
	_register_item("test_panel_cap", ["equip_head"])
	player.inventory.add("test_panel_cap", 1)

	_panel.open()

	assert_bool((_item_rows()[0].get_node("%EquipButton") as Button).visible).is_true()


func test_equip_row_moves_the_item_into_the_strip() -> void:
	var player := _make_panel()
	_register_item("test_panel_axe", ["tool"])
	player.inventory.add("test_panel_axe", 1)
	_panel.open()

	(_item_rows()[0] as InventoryItemRow).equip_pressed.emit()
	await get_tree().process_frame

	assert_int(_equipped_rows().size()).is_equal(1)
	assert_int(_item_rows().size()).is_equal(0)


func test_open_and_close_register_with_the_ui_gate() -> void:
	_make_panel()

	_panel.open()
	assert_bool(UiGate.is_input_blocked()).is_true()
	assert_bool(_panel.is_open()).is_true()

	_panel.close()
	assert_bool(UiGate.is_input_blocked()).is_false()
	assert_bool(_panel.is_open()).is_false()


func test_equip_failure_text_names_the_reason() -> void:
	assert_str(InventoryPanel.equip_failure_text(Equipment.EquipResult.NO_ROOM, "Axe")).contains("room")
	assert_str(InventoryPanel.equip_failure_text(Equipment.EquipResult.ALREADY_HELD, "Axe")).contains("Axe")
	assert_str(InventoryPanel.equip_failure_text(Equipment.EquipResult.NO_SLOT, "Axe")).contains("Axe")
	assert_str(InventoryPanel.equip_failure_text(Equipment.EquipResult.NOT_CARRIED, "Axe")).contains("Axe")
	assert_str(InventoryPanel.equip_failure_text(Equipment.EquipResult.OK, "Axe")).is_empty()


func test_carried_list_is_ordered_by_category_then_name() -> void:
	# Break caught: iterating the inventory dictionary shows stacks in whatever order they were added.
	var player := _make_panel()
	var ration := _register_item("test_panel_mmm_ration", ["material"])
	ration.food = auto_free(FoodParams.new())
	_register_item("test_panel_aaa_rock", ["material"])
	_register_item("test_panel_zzz_axe", ["tool"])
	# Added in an order that is not the display order.
	player.inventory.add("test_panel_aaa_rock", 1)
	player.inventory.add("test_panel_mmm_ration", 1)
	player.inventory.add("test_panel_zzz_axe", 1)

	_panel.open()

	var names: Array[String] = []
	for row: Node in _item_rows():
		names.append((row.get_node("%NameLabel") as Label).text)
	assert_array(names).is_equal(["test_panel_zzz_axe", "test_panel_mmm_ration", "test_panel_aaa_rock"])


func test_keyboard_focus_stays_on_the_same_button_after_an_action() -> void:
	# Break caught: every change rebuilds the rows, so a keyboard user would lose focus after each Enter.
	var player := _make_panel()
	var ration := _register_item("test_panel_ration", ["material"])
	ration.food = auto_free(FoodParams.new())
	player.inventory.add("test_panel_ration", 3)
	_panel.open()
	var eat_button := _item_rows()[0].get_node("%EatButton") as Button
	eat_button.grab_focus()

	eat_button.pressed.emit()
	await get_tree().process_frame

	assert_int(player.inventory.get_item_count("test_panel_ration")).is_equal(2)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(_item_rows()[0].get_node("%EatButton"))


func test_drop_button_drops_one_unit_and_spawns_a_world_item() -> void:
	var player := _make_panel()
	_register_item("test_panel_gravel", ["material"], 0.5)
	player.inventory.add("test_panel_gravel", 3)
	_panel.open()

	var row := _item_rows()[0] as InventoryItemRow
	(row.get_node("%DropButton") as Button).pressed.emit()
	await get_tree().process_frame

	assert_int(player.inventory.get_item_count("test_panel_gravel")).is_equal(2)
	var dropped := _find_world_item("test_panel_gravel")
	assert_object(dropped).is_not_null()
	assert_int(dropped.count).is_equal(1)
	auto_free(dropped)


func test_drop_all_button_drops_the_entire_carried_stack() -> void:
	var player := _make_panel()
	_register_item("test_panel_sand", ["material"], 0.5)
	player.inventory.add("test_panel_sand", 3)
	_panel.open()

	var row := _item_rows()[0] as InventoryItemRow
	(row.get_node("%DropAllButton") as Button).pressed.emit()
	await get_tree().process_frame

	assert_int(player.inventory.get_item_count("test_panel_sand")).is_equal(0)
	var dropped := _find_world_item("test_panel_sand")
	assert_object(dropped).is_not_null()
	assert_int(dropped.count).is_equal(3)
	auto_free(dropped)
