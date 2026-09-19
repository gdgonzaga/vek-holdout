extends GdUnitTestSuite
## Tests for the Gear sub-tab: ColonistEquipmentPanel (slot list + side picker),
## EquipmentSlotRow and EquipmentPickerRow.
## Content-agnostic: items are synthetic and registered in ItemDB only for each test's
## duration (swap-and-restore), and the storage registry / job board are sandbox-owned.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const PANEL_SCENE: PackedScene = preload("res://ui/colony_management/colonist_equipment_panel.tscn")
const PICKER_ROW_SCENE: PackedScene = preload("res://ui/colony_management/equipment_picker_row.tscn")

const TOOL_ID: String = "gear_panel_tool"
const OTHER_TOOL_ID: String = "gear_panel_other_tool"
const HELM_ID: String = "gear_panel_helm"

var _sandbox: ColonySandbox
var _previous_item_defs: Dictionary = {}


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	_make_item(TOOL_ID, ["tool"], "Alpha Tool")
	_make_item(OTHER_TOOL_ID, ["tool"], "Beta Tool")
	_make_item(HELM_ID, ["equip_head"], "Test Helm")


func after_test() -> void:
	for id_val: String in _previous_item_defs:
		if _previous_item_defs[id_val] != null:
			ItemDB._defs_by_id[id_val] = _previous_item_defs[id_val]
		else:
			ItemDB._defs_by_id.erase(id_val)
	_previous_item_defs.clear()
	_sandbox.restore()


# ==============================
# Helpers
# ==============================

func _make_item(id_val: String, item_tags: Array[String], display: String) -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = id_val
	def.tags = item_tags
	def.weight = 1.0
	def.resource_name = display
	if not _previous_item_defs.has(id_val):
		_previous_item_defs[id_val] = ItemDB._defs_by_id.get(id_val, null)
	ItemDB._defs_by_id[id_val] = def
	return def


func _make_panel(colonist: Colonist) -> ColonistEquipmentPanel:
	var panel: ColonistEquipmentPanel = auto_free(PANEL_SCENE.instantiate() as ColonistEquipmentPanel)
	add_child(panel)
	panel.set_colonist(colonist)
	return panel


func _row(panel: ColonistEquipmentPanel, slot_id: String) -> EquipmentSlotRow:
	var container: VBoxContainer = panel.get_node("%SlotsContainer") as VBoxContainer
	for row: EquipmentSlotRow in container.get_children():
		if row.get_slot_id() == slot_id:
			return row
	return null


func _picker_ids(panel: ColonistEquipmentPanel) -> Array[String]:
	var out: Array[String] = []
	var items: VBoxContainer = panel.get_node("%ItemsContainer") as VBoxContainer
	for child: Node in items.get_children():
		if child is EquipmentPickerRow:
			out.append((child as EquipmentPickerRow).get_item_id())
	return out


func _picker_row(panel: ColonistEquipmentPanel, item_id: String) -> EquipmentPickerRow:
	var items: VBoxContainer = panel.get_node("%ItemsContainer") as VBoxContainer
	for child: Node in items.get_children():
		if child is EquipmentPickerRow and (child as EquipmentPickerRow).get_item_id() == item_id:
			return child as EquipmentPickerRow
	return null


func _show_everything(panel: ColonistEquipmentPanel) -> void:
	var toggle: CheckButton = panel.get_node("%InColonyToggle") as CheckButton
	toggle.button_pressed = false


func _cancel_event() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	return ev


# ==============================
# Slot list
# ==============================

func test_renders_eight_slot_rows() -> void:
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())

	var container: VBoxContainer = panel.get_node("%SlotsContainer") as VBoxContainer
	assert_int(container.get_child_count()).is_equal(8)


func test_slot_row_shows_equipped_item_name() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var panel: ColonistEquipmentPanel = _make_panel(colonist)

	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, ItemDB.get_def(TOOL_ID))

	var label: Label = _row(panel, Equipment.SLOT_MAIN_HAND).get_node("%EquippedLabel") as Label
	assert_str(label.text).is_equal("Alpha Tool")


func test_slot_row_shows_pending_target_and_status_tooltip() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var panel: ColonistEquipmentPanel = _make_panel(colonist)

	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, TOOL_ID)

	var row: EquipmentSlotRow = _row(panel, Equipment.SLOT_MAIN_HAND)
	var target: Label = row.get_node("%TargetLabel") as Label
	assert_str(target.text).contains("Alpha Tool")
	assert_str(row.tooltip_text).is_equal("None in storage")


func test_slot_row_hides_target_text_when_target_is_met() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var panel: ColonistEquipmentPanel = _make_panel(colonist)
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, ItemDB.get_def(TOOL_ID))

	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, TOOL_ID)

	var target: Label = _row(panel, Equipment.SLOT_MAIN_HAND).get_node("%TargetLabel") as Label
	assert_str(target.text).is_equal("")


func test_slot_rows_refresh_from_equipment_signals_without_a_manual_refresh() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var panel: ColonistEquipmentPanel = _make_panel(colonist)

	colonist.equipment.equip(Equipment.SLOT_HEAD, ItemDB.get_def(HELM_ID))

	var label: Label = _row(panel, Equipment.SLOT_HEAD).get_node("%EquippedLabel") as Label
	assert_str(label.text).is_equal("Test Helm")


func _panel_listens_to(signal_ref: Signal, panel: ColonistEquipmentPanel) -> bool:
	for connection: Dictionary in signal_ref.get_connections():
		var callable: Callable = connection["callable"]
		if callable.get_object() == panel:
			return true
	return false


func test_set_colonist_moves_the_signal_connections_to_the_new_colonist() -> void:
	var first: Colonist = _sandbox.make_colonist()
	var second: Colonist = _sandbox.make_colonist()
	var panel: ColonistEquipmentPanel = _make_panel(first)
	assert_bool(_panel_listens_to(first.equipment.slot_changed, panel)).is_true()

	panel.set_colonist(second)

	assert_bool(_panel_listens_to(first.equipment.slot_changed, panel)).is_false()
	assert_bool(_panel_listens_to(first.equipment.desired_slot_changed, panel)).is_false()
	assert_bool(_panel_listens_to(second.equipment.slot_changed, panel)).is_true()
	assert_bool(_panel_listens_to(second.equipment.desired_slot_changed, panel)).is_true()


# ==============================
# Picker pane
# ==============================

func test_picker_starts_on_placeholder_with_no_slot_selected() -> void:
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())

	assert_str(panel.get_active_slot()).is_equal("")
	assert_bool((panel.get_node("%PickerPlaceholder") as Control).visible).is_true()
	assert_bool((panel.get_node("%PickerContent") as Control).visible).is_false()


func test_pressing_a_slot_row_selects_it_and_shows_the_picker() -> void:
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())

	_row(panel, Equipment.SLOT_MAIN_HAND).pressed.emit()

	assert_str(panel.get_active_slot()).is_equal(Equipment.SLOT_MAIN_HAND)
	assert_bool((panel.get_node("%PickerContent") as Control).visible).is_true()
	assert_bool((panel.get_node("%PickerPlaceholder") as Control).visible).is_false()


func test_picker_lists_only_items_eligible_for_the_selected_slot() -> void:
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())
	_show_everything(panel)

	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	var ids: Array[String] = _picker_ids(panel)
	assert_array(ids).contains([TOOL_ID, OTHER_TOOL_ID])
	assert_array(ids).not_contains([HELM_ID])


func test_in_colony_toggle_defaults_on_and_hides_items_the_colony_lacks() -> void:
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())

	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	assert_bool((panel.get_node("%InColonyToggle") as CheckButton).button_pressed).is_true()
	assert_array(_picker_ids(panel)).not_contains([TOOL_ID])


func test_in_colony_filter_lists_items_held_in_crates() -> void:
	_sandbox.make_crate(TOOL_ID, 2)
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())

	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	assert_array(_picker_ids(panel)).contains([TOOL_ID])
	assert_array(_picker_ids(panel)).not_contains([OTHER_TOOL_ID])


func test_search_narrows_the_picker_list() -> void:
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())
	_show_everything(panel)
	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	var search: LineEdit = panel.get_node("%SearchInput") as LineEdit
	search.text = "beta"
	search.text_changed.emit("beta")

	var ids: Array[String] = _picker_ids(panel)
	assert_array(ids).contains([OTHER_TOOL_ID])
	assert_array(ids).not_contains([TOOL_ID])


func test_picker_stock_label_shows_crate_count() -> void:
	_sandbox.make_crate(TOOL_ID, 3)
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())

	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	var stock: Label = _picker_row(panel, TOOL_ID).get_node("%StockLabel") as Label
	assert_str(stock.text).is_equal("x3")


# ==============================
# Choosing, clearing, unequipping
# ==============================

func test_choosing_an_item_sets_the_target_and_keeps_the_slot_selected() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var panel: ColonistEquipmentPanel = _make_panel(colonist)
	_show_everything(panel)
	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	_picker_row(panel, TOOL_ID).chosen.emit(TOOL_ID)

	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal(TOOL_ID)
	assert_str(panel.get_active_slot()).is_equal(Equipment.SLOT_MAIN_HAND)


func test_chosen_target_is_marked_in_the_picker() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var panel: ColonistEquipmentPanel = _make_panel(colonist)
	_show_everything(panel)
	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	_picker_row(panel, TOOL_ID).chosen.emit(TOOL_ID)

	var mark: Label = _picker_row(panel, TOOL_ID).get_node("%MarkLabel") as Label
	assert_str(mark.text).contains("target")


func test_clear_target_button_clears_the_target() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var panel: ColonistEquipmentPanel = _make_panel(colonist)
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, TOOL_ID)
	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	(panel.get_node("%ClearTargetButton") as Button).pressed.emit()

	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("")


func test_clear_target_button_is_disabled_without_a_target() -> void:
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())

	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	assert_bool((panel.get_node("%ClearTargetButton") as Button).disabled).is_true()


func test_unequip_is_disabled_for_an_empty_slot() -> void:
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())

	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	assert_bool((panel.get_node("%UnequipButton") as Button).disabled).is_true()


func test_unequip_is_disabled_while_the_slot_has_a_target() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var panel: ColonistEquipmentPanel = _make_panel(colonist)
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, ItemDB.get_def(TOOL_ID))
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, TOOL_ID)

	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	var button: Button = panel.get_node("%UnequipButton") as Button
	assert_bool(button.disabled).is_true()
	assert_str(button.tooltip_text).is_not_empty()


func test_unequip_moves_the_item_into_pockets_when_no_target_is_set() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var panel: ColonistEquipmentPanel = _make_panel(colonist)
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, ItemDB.get_def(TOOL_ID))
	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	(panel.get_node("%UnequipButton") as Button).pressed.emit()

	assert_bool(colonist.equipment.is_empty(Equipment.SLOT_MAIN_HAND)).is_true()
	assert_bool(colonist.inventory.has_item(TOOL_ID, 1)).is_true()


func test_status_reason_label_explains_a_pending_target() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var panel: ColonistEquipmentPanel = _make_panel(colonist)
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, TOOL_ID)

	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	var reason: Label = panel.get_node("%StatusReasonLabel") as Label
	assert_str(reason.text).is_equal("None in storage")


# ==============================
# Esc handling
# ==============================

func test_cancel_closes_the_picker_and_reports_it_consumed_the_press() -> void:
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())
	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	var consumed: bool = panel.handle_cancel()

	assert_bool(consumed).is_true()
	assert_str(panel.get_active_slot()).is_equal("")
	assert_bool((panel.get_node("%PickerContent") as Control).visible).is_false()


func test_cancel_with_no_slot_selected_is_left_for_the_screen_to_handle() -> void:
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())

	assert_bool(panel.handle_cancel()).is_false()


func test_cancel_action_reaches_handle_cancel_through_unhandled_input() -> void:
	var panel: ColonistEquipmentPanel = _make_panel(_sandbox.make_colonist())
	panel.select_slot(Equipment.SLOT_MAIN_HAND)

	panel._unhandled_input(_cancel_event())

	assert_str(panel.get_active_slot()).is_equal("")


# ==============================
# EquipmentPickerRow
# ==============================

func test_picker_row_shows_name_stock_and_glyph_fallback() -> void:
	var entry := GearPickerModel.Entry.new()
	entry.def = ItemDB.get_def(TOOL_ID)
	entry.stock = 0
	var row: EquipmentPickerRow = auto_free(PICKER_ROW_SCENE.instantiate() as EquipmentPickerRow)
	add_child(row)

	row.setup(entry)

	assert_str((row.get_node("%NameLabel") as Label).text).is_equal("Alpha Tool")
	assert_str((row.get_node("%StockLabel") as Label).text).is_equal("none")
	assert_str((row.get_node("%IconFallbackLabel") as Label).text).is_equal("A")
	assert_bool((row.get_node("%IconFallbackLabel") as Label).visible).is_true()


func test_picker_row_refresh_stock_updates_in_place() -> void:
	var entry := GearPickerModel.Entry.new()
	entry.def = ItemDB.get_def(TOOL_ID)
	var row: EquipmentPickerRow = auto_free(PICKER_ROW_SCENE.instantiate() as EquipmentPickerRow)
	add_child(row)
	row.setup(entry)

	row.refresh_stock(4)

	assert_str((row.get_node("%StockLabel") as Label).text).is_equal("x4")


func test_picker_row_press_emits_chosen_with_its_item_id() -> void:
	var entry := GearPickerModel.Entry.new()
	entry.def = ItemDB.get_def(TOOL_ID)
	var row: EquipmentPickerRow = auto_free(PICKER_ROW_SCENE.instantiate() as EquipmentPickerRow)
	add_child(row)
	row.setup(entry)
	var received: Array[String] = []
	row.chosen.connect(func(item_id: String) -> void: received.append(item_id))

	row.pressed.emit()

	assert_array(received).is_equal([TOOL_ID])
