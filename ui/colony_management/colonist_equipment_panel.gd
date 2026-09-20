class_name ColonistEquipmentPanel
extends HBoxContainer
## Gear sub-tab body: a compact slot list on the left and an always-visible picker pane on the
## right. Selecting a slot row opens that slot in the picker; choosing an item sets the slot's
## target (Equipment desired item). Rows and the slot-state box refresh from the colonist's
## Equipment signals instead of polling. Only storage-dependent text (status reasons, stock
## counts) needs the owner's slow tick, which just calls refresh_display().

const SLOT_ROW_SCENE: PackedScene = preload("res://ui/colony_management/equipment_slot_row.tscn")
const PICKER_ROW_SCENE: PackedScene = preload("res://ui/colony_management/equipment_picker_row.tscn")

const SLOTS: Array[String] = [
	Equipment.SLOT_HEAD,
	Equipment.SLOT_TORSO,
	Equipment.SLOT_LEGS,
	Equipment.SLOT_FEET,
	Equipment.SLOT_MAIN_HAND,
	Equipment.SLOT_OFF_HAND,
	Equipment.SLOT_HOLSTER,
	Equipment.SLOT_BACK,
]

const EMPTY_TEXT: String = "(empty)"
const NO_TARGET_TEXT: String = "(none)"
const UNEQUIP_LOCKED_TOOLTIP: String = "Clear the target first; the colonist would re-equip it."
const COLOR_GROUP_HEADER: Color = Color(0.9, 0.85, 0.6, 1.0)

var _colonist: Colonist = null
var _active_slot: String = ""
var _row_instances: Dictionary = {} # slot_id -> EquipmentSlotRow

@onready var _loadout_strip: LoadoutStrip = %LoadoutStrip
@onready var _slots_container: VBoxContainer = %SlotsContainer
@onready var _picker_placeholder: Label = %PickerPlaceholder
@onready var _picker_content: VBoxContainer = %PickerContent
@onready var _picker_title: Label = %PickerTitle
@onready var _equipped_value_label: Label = %EquippedValueLabel
@onready var _unequip_button: Button = %UnequipButton
@onready var _target_value_label: Label = %TargetValueLabel
@onready var _clear_target_button: Button = %ClearTargetButton
@onready var _status_reason_label: Label = %StatusReasonLabel
@onready var _search_input: LineEdit = %SearchInput
@onready var _in_colony_toggle: CheckButton = %InColonyToggle
@onready var _items_container: VBoxContainer = %ItemsContainer
@onready var _empty_list_label: Label = %EmptyListLabel

# =================
# Primary Functions
# =================

func _ready() -> void:
	# 1. Slot Rows: build the 8 fixed slot tiles once; their content is bound per colonist.
	_instantiate_slot_rows()

	# 2. Picker Events: wire buttons, search and toggle so the pane reacts without polling.
	_connect_picker_events()

	# 3. Initial View: no slot is selected yet, so show the hint instead of an empty picker.
	_apply_selection_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or not is_visible_in_tree():
		return

	# 1. Cancel Handling: Esc backs out of the picker first, so it only reaches the screen when nothing is selected.
	if handle_cancel():
		get_viewport().set_input_as_handled()


## Points the panel at a colonist (or null) and drops any slot selection from the previous one.
func set_colonist(colonist: Colonist) -> void:
	# 1. Signal Handover: stop listening to the previous colonist before binding the new one.
	_disconnect_equipment_signals(_colonist)
	_colonist = colonist
	_connect_equipment_signals(_colonist)

	# 2. Row Binding: point every slot tile at the new colonist.
	_bind_rows(_colonist)

	# 3. Loadout Strip: apply and save act on whichever colonist is shown, so rebind it too.
	_loadout_strip.set_colonist(_colonist)

	# 4. Selection Reset: a slot selection belongs to one colonist, so drop it on switch.
	deselect_slot()

	# 5. Display Refresh: bring rows and status text in line with the new colonist's gear.
	refresh_display()


## Re-evaluates everything that depends on live state: rows, the slot-state box and picker stock.
## Called on Equipment signals and by the owner's slow tick (storage has no signal).
func refresh_display() -> void:
	if _colonist == null or not is_instance_valid(_colonist):
		visible = false
		return
	visible = true

	# 1. Rows: re-evaluate every slot tile (equipped item, pending target, status pip).
	_refresh_rows()

	# 2. Slot State: refresh the pane's equipped/target/status box for the selected slot.
	_refresh_slot_state()

	# 3. Stock Counts: update crate stock on existing picker rows in place, without a rebuild.
	_refresh_picker_stock()


## Opens `slot_id` in the picker pane with an unfiltered list.
func select_slot(slot_id: String) -> void:
	if not SLOTS.has(slot_id) or _colonist == null:
		return
	_active_slot = slot_id

	# 1. Selection View: swap the hint for the picker and highlight the chosen row.
	_apply_selection_visibility()
	_mark_selected_row()

	# 2. Fresh Search: a newly selected slot starts unfiltered (setting text emits no signal).
	_search_input.text = ""

	# 3. Slot State: show what this slot wears and wants before the list.
	_refresh_slot_state()

	# 4. Item List: build the grouped, sorted candidates for this slot.
	_rebuild_picker()


## Closes the picker pane and clears the row highlight.
func deselect_slot() -> void:
	_active_slot = ""
	_apply_selection_visibility()
	_mark_selected_row()


func get_active_slot() -> String:
	return _active_slot


## Esc handling: closes the picker if a slot is selected. Returns true when it consumed the
## press, so the screen only sees Esc when there is nothing left to back out of.
func handle_cancel() -> bool:
	if _active_slot.is_empty():
		return false
	deselect_slot()
	return true

# ===================
# Auxiliary Functions
# ===================

func _instantiate_slot_rows() -> void:
	## Auxiliary: Creates one EquipmentSlotRow per slot and routes its selection to select_slot.
	for slot_id: String in SLOTS:
		var row: EquipmentSlotRow = SLOT_ROW_SCENE.instantiate() as EquipmentSlotRow
		_slots_container.add_child(row)
		row.setup(slot_id, null)
		row.selected.connect(select_slot)
		_row_instances[slot_id] = row


func _connect_picker_events() -> void:
	## Auxiliary: Connects the picker pane's buttons, search field and In-colony toggle.
	_unequip_button.pressed.connect(_on_unequip_pressed)
	_clear_target_button.pressed.connect(_on_clear_target_pressed)
	_search_input.text_changed.connect(_on_search_changed)
	_in_colony_toggle.toggled.connect(_on_in_colony_toggled)


func _connect_equipment_signals(colonist: Colonist) -> void:
	## Auxiliary: Listens to slot and target changes so rows update without polling.
	if colonist == null or not is_instance_valid(colonist) or colonist.equipment == null:
		return
	colonist.equipment.slot_changed.connect(_on_equipment_changed)
	colonist.equipment.desired_slot_changed.connect(_on_equipment_changed)


func _disconnect_equipment_signals(colonist: Colonist) -> void:
	## Auxiliary: Stops listening to a colonist we are no longer showing.
	if colonist == null or not is_instance_valid(colonist) or colonist.equipment == null:
		return
	if colonist.equipment.slot_changed.is_connected(_on_equipment_changed):
		colonist.equipment.slot_changed.disconnect(_on_equipment_changed)
	if colonist.equipment.desired_slot_changed.is_connected(_on_equipment_changed):
		colonist.equipment.desired_slot_changed.disconnect(_on_equipment_changed)


func _on_equipment_changed(slot_id: String, _payload: Variant) -> void:
	## Auxiliary: Equipment reported a slot or target change (payload is an ItemDef or an id).
	refresh_display()
	if slot_id == _active_slot:
		_rebuild_picker()


func _bind_rows(colonist: Colonist) -> void:
	## Auxiliary: Re-points every slot tile at `colonist` and renders it.
	for slot_id: String in SLOTS:
		var row: EquipmentSlotRow = _row_instances[slot_id]
		row.setup(slot_id, colonist)


func _refresh_rows() -> void:
	## Auxiliary: Re-renders every slot tile from current colonist state.
	for slot_id: String in SLOTS:
		var row: EquipmentSlotRow = _row_instances[slot_id]
		row.refresh()


func _mark_selected_row() -> void:
	## Auxiliary: Highlights only the row whose slot is open in the picker.
	for slot_id: String in SLOTS:
		var row: EquipmentSlotRow = _row_instances[slot_id]
		row.set_selected(slot_id == _active_slot)


func _apply_selection_visibility() -> void:
	## Auxiliary: Shows the hint when no slot is selected, otherwise the picker content.
	_picker_placeholder.visible = _active_slot.is_empty()
	_picker_content.visible = not _active_slot.is_empty()


func _refresh_slot_state() -> void:
	## Auxiliary: Fills the pane's title, equipped/target values, action buttons and status reason.
	if _active_slot.is_empty() or _colonist == null or not is_instance_valid(_colonist):
		return
	if _colonist.equipment == null:
		return
	var equipped: ItemDef = _colonist.equipment.get_item(_active_slot)
	var target_id: String = _colonist.equipment.get_desired_item(_active_slot)
	_picker_title.text = "%s: choose target" % GearText.slot_display_name(_active_slot)

	# 1. Values: what the slot wears and what it is set to want.
	_show_slot_values(equipped, target_id)

	# 2. Actions: Unequip and Clear are enabled only when they would do something.
	_update_action_buttons(equipped != null, not target_id.is_empty())

	# 3. Status: the reason the target is met or still pending.
	_show_status_reason()


func _show_slot_values(equipped: ItemDef, target_id: String) -> void:
	## Auxiliary: Writes the equipped and target names, with muted placeholders when there are none.
	_equipped_value_label.text = equipped.get_display_name() if equipped != null else EMPTY_TEXT
	_target_value_label.text = _target_display_name(target_id) if not target_id.is_empty() else NO_TARGET_TEXT


func _update_action_buttons(has_equipped: bool, has_target: bool) -> void:
	## Auxiliary: Unequip is locked while a target is set (the audit would re-equip it); Clear needs a target.
	_unequip_button.disabled = not has_equipped or has_target
	_unequip_button.tooltip_text = UNEQUIP_LOCKED_TOOLTIP if has_target else ""
	_clear_target_button.disabled = not has_target


func _show_status_reason() -> void:
	## Auxiliary: Writes the selected slot's GearStatus text, colored by state.
	var result: GearStatus.Result = GearStatus.evaluate(
			_colonist, _active_slot, Colony.storage_registry, Colony.job_board)
	_status_reason_label.text = result.text
	_status_reason_label.add_theme_color_override("font_color", result.color)


func _target_display_name(target_id: String) -> String:
	## Auxiliary: Name of a target item, falling back to its raw id if the def no longer exists.
	return ItemDB.get_display_name(target_id)


func _rebuild_picker() -> void:
	## Auxiliary: Rebuilds the item list for the selected slot from the picker model.
	if _active_slot.is_empty() or _colonist == null or _colonist.equipment == null:
		return
	_clear_children(_items_container)

	# 1. Entry Model: filter, group and sort the eligible items against a fresh crate-stock snapshot.
	var entries: Array[GearPickerModel.Entry] = _build_entries()

	# 2. Row Creation: one header per group, one scene-based row per entry.
	_add_entry_rows(entries)

	# 3. Empty State: explain an empty list instead of showing a blank pane.
	_update_empty_message(entries.is_empty())


func _build_entries() -> Array[GearPickerModel.Entry]:
	## Auxiliary: Asks the picker model for the selected slot's entries under the current search and toggle.
	var eligible: Array[ItemDef] = Equipment.get_eligible_items_for_slot(_active_slot)
	return GearPickerModel.build_entries(
			eligible,
			Equipment.SLOT_ACCEPTED_TAGS.get(_active_slot, []),
			_search_input.text,
			_in_colony_toggle.button_pressed,
			_collect_stock(eligible),
			_colonist.equipment.get_desired_item(_active_slot),
			_equipped_id(_active_slot))


func _equipped_id(slot_id: String) -> String:
	## Auxiliary: Id of the item in `slot_id`, or "" when the slot is empty.
	var equipped: ItemDef = _colonist.equipment.get_item(slot_id)
	return equipped.id if equipped != null else ""


func _collect_stock(eligible: Array[ItemDef]) -> Dictionary:
	## Auxiliary: Crate stock per eligible item id, empty when there is no registry.
	var stock: Dictionary = {}
	for def: ItemDef in eligible:
		if def != null:
			stock[def.id] = _crate_stock(def.id)
	return stock


func _crate_stock(item_id: String) -> int:
	## Auxiliary: Items of `item_id` a fetch job could take from crates (0 without a registry).
	if Colony.storage_registry == null:
		return 0
	return Colony.storage_registry.crate_stock(item_id)


func _add_entry_rows(entries: Array[GearPickerModel.Entry]) -> void:
	## Auxiliary: Adds a group header whenever the group changes, then the entry's row.
	var current_group: String = ""
	for entry: GearPickerModel.Entry in entries:
		if entry.group != current_group:
			current_group = entry.group
			_add_group_header(current_group)
		_add_picker_row(entry)


func _add_group_header(group_text: String) -> void:
	## Auxiliary: A small muted label separating groups in the list.
	var header := Label.new()
	header.text = group_text.to_upper()
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", COLOR_GROUP_HEADER)
	_items_container.add_child(header)


func _add_picker_row(entry: GearPickerModel.Entry) -> void:
	## Auxiliary: Instances a picker row scene for `entry` and routes its choice to the target.
	var row: EquipmentPickerRow = PICKER_ROW_SCENE.instantiate() as EquipmentPickerRow
	_items_container.add_child(row)
	row.setup(entry)
	row.chosen.connect(_on_item_chosen)


func _update_empty_message(is_empty: bool) -> void:
	## Auxiliary: Shows why the list is empty, pointing at the In-colony toggle when it is the likely cause.
	_empty_list_label.visible = is_empty
	if not is_empty:
		return
	if _search_input.text.strip_edges().is_empty() and _in_colony_toggle.button_pressed:
		_empty_list_label.text = "Nothing in colony storage fits this slot. Turn off \"In colony only\" to see every item."
	else:
		_empty_list_label.text = "No items match."


func _refresh_picker_stock() -> void:
	## Auxiliary: Updates stock labels on the existing rows so the list never flickers or loses scroll.
	if _active_slot.is_empty():
		return
	for child: Node in _items_container.get_children():
		var row := child as EquipmentPickerRow
		if row != null:
			row.refresh_stock(_crate_stock(row.get_item_id()))


func _clear_children(container: Container) -> void:
	## Auxiliary: Removes children immediately (not just queue_free) so a rebuild never shows stale rows.
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_item_chosen(item_id: String) -> void:
	## Auxiliary: Sets the selected slot's target; Equipment's signal refreshes rows and the list.
	if _colonist == null or _colonist.equipment == null or _active_slot.is_empty():
		return
	_colonist.equipment.set_desired_item(_active_slot, item_id)


func _on_clear_target_pressed() -> void:
	## Auxiliary: Clears the selected slot's target.
	if _colonist == null or _colonist.equipment == null or _active_slot.is_empty():
		return
	_colonist.equipment.clear_desired_item(_active_slot)


func _on_unequip_pressed() -> void:
	## Auxiliary: Unequips the selected slot's item and keeps it (pockets, else dropped at the colonist).
	if _colonist == null or _colonist.equipment == null or _active_slot.is_empty():
		return
	var item: ItemDef = _colonist.equipment.unequip(_active_slot)
	if item != null:
		# 1. Item Preservation: an unequipped item must never vanish, so stow it or drop it in the world.
		_safely_stow_or_drop_item(_colonist, item)


func _safely_stow_or_drop_item(colonist: Colonist, item: ItemDef) -> void:
	## Auxiliary: Adds item to colonist inventory if capacity permits, otherwise spawns a WorldItem on the floor.
	if colonist.inventory != null and colonist.inventory.can_add(item.id, 1):
		colonist.inventory.add(item.id, 1)
		return
	if colonist.is_inside_tree():
		WorldItem.spawn_at(colonist, item.id, 1, colonist.global_position + Vector3(0, 0.5, 0))


func _on_search_changed(_new_text: String) -> void:
	_rebuild_picker()


func _on_in_colony_toggled(_is_pressed: bool) -> void:
	_rebuild_picker()
