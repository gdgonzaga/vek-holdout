class_name ColonistEquipmentPanel
extends VBoxContainer
## Equipment and loadout configuration panel for a selected colonist.
## Displays currently equipped gear across 8 slots and hosts a filterable
## desired-item selector to assign loadout targets.

const SLOT_ROW_SCENE: PackedScene = preload("res://ui/colony_management/equipment_slot_row.tscn")

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

var _colonist: Colonist = null
var _active_slot: String = ""
var _row_instances: Dictionary = {} # slot_id -> EquipmentSlotRow

@onready var _slots_container: VBoxContainer = %SlotsContainer
@onready var _desired_picker_section: Control = %DesiredPickerSection
@onready var _picker_title: Label = %PickerTitle
@onready var _search_input: LineEdit = %SearchInput
@onready var _items_container: VBoxContainer = %ItemsContainer
@onready var _close_picker_button: Button = %ClosePickerButton

# ================
# Primary Functions
# ================

func _ready() -> void:
	# 1. UI Setup: Connect picker controls and instantiate static slot rows.
	_connect_picker_events()
	_instantiate_slot_rows()


## Configures the panel for the specified colonist and refreshes all slot rows.
func set_colonist(colonist: Colonist) -> void:
	_colonist = colonist

	# 1. Picker Reset: Close open picker if colonist changes.
	_close_picker()

	# 2. Display Refresh: Update row contents to match colonist equipment.
	refresh_display()


## Updates row contents and re-populates the picker if open.
func refresh_display() -> void:
	if _colonist == null or not is_instance_valid(_colonist):
		visible = false
		return

	visible = true

	# 1. Row Refresh: Refresh each slot row with colonist gear state.
	for slot_id: String in SLOTS:
		if _row_instances.has(slot_id):
			var row: EquipmentSlotRow = _row_instances[slot_id]
			row.setup(slot_id, _colonist)

	# 2. Picker Refresh: If item picker is currently active, refresh its list.
	if _desired_picker_section != null and _desired_picker_section.visible and not _active_slot.is_empty():
		_populate_picker_items(_search_input.text if _search_input != null else "")

# ====================
# Auxiliary Functions
# ====================

func _connect_picker_events() -> void:
	## Auxiliary: Connects search input and close button events for the desired item picker.
	if _close_picker_button != null and not _close_picker_button.pressed.is_connected(_close_picker):
		_close_picker_button.pressed.connect(_close_picker)
	if _search_input != null and not _search_input.text_changed.is_connected(_on_search_changed):
		_search_input.text_changed.connect(_on_search_changed)


func _instantiate_slot_rows() -> void:
	## Auxiliary: Instantiates the 8 canonical EquipmentSlotRow components inside SlotsContainer.
	if _slots_container == null:
		return

	for child in _slots_container.get_children():
		child.queue_free()
	_row_instances.clear()

	for slot_id: String in SLOTS:
		var row: EquipmentSlotRow = SLOT_ROW_SCENE.instantiate() as EquipmentSlotRow
		_slots_container.add_child(row)
		_row_instances[slot_id] = row
		row.edit_requested.connect(_on_slot_edit_requested)
		row.clear_requested.connect(_on_slot_clear_requested)
		row.unequip_requested.connect(_on_slot_unequip_requested)


func _on_slot_edit_requested(slot_id: String) -> void:
	## Auxiliary: Handles click on "Set Target" button for a slot.
	_active_slot = slot_id
	if _picker_title != null:
		_picker_title.text = "Set Desired Item: %s" % slot_id.replace("_", " ").capitalize()
	if _search_input != null:
		_search_input.text = ""
	if _desired_picker_section != null:
		_desired_picker_section.visible = true

	# 1. Item Population: Query eligible items from Equipment and display filterable list.
	_populate_picker_items("")


func _on_slot_clear_requested(slot_id: String) -> void:
	## Auxiliary: Clears the desired target item for a slot.
	if _colonist == null or _colonist.equipment == null:
		return
	_colonist.equipment.clear_desired_item(slot_id)
	if _row_instances.has(slot_id):
		_row_instances[slot_id].refresh()
	if _active_slot == slot_id and _desired_picker_section != null and _desired_picker_section.visible:
		_populate_picker_items(_search_input.text if _search_input != null else "")


func _on_slot_unequip_requested(slot_id: String) -> void:
	## Auxiliary: Unequips the currently equipped item in a slot.
	if _colonist == null or _colonist.equipment == null:
		return
	var item: ItemDef = _colonist.equipment.unequip(slot_id)
	if item != null:
		# 1. Item Preservation: Place unequipped item into pockets or drop in world if inventory is full.
		_safely_stow_or_drop_item(_colonist, item)
	if _row_instances.has(slot_id):
		_row_instances[slot_id].refresh()


func _safely_stow_or_drop_item(colonist: Colonist, item: ItemDef) -> void:
	## Auxiliary: Adds item to colonist inventory if capacity permits, otherwise spawns WorldItem on floor.
	if colonist.inventory != null and colonist.inventory.can_add(item.id, 1):
		colonist.inventory.add(item.id, 1)
		return
	if colonist.is_inside_tree():
		WorldItem.spawn_at(colonist, item.id, 1, colonist.global_position + Vector3(0, 0.5, 0))


func _close_picker() -> void:
	## Auxiliary: Closes and hides the desired item picker sub-panel.
	_active_slot = ""
	if _desired_picker_section != null:
		_desired_picker_section.visible = false


func _on_search_changed(new_text: String) -> void:
	## Auxiliary: Reacts to search input typing by updating the filtered items list.
	_populate_picker_items(new_text)


func _populate_picker_items(filter_text: String) -> void:
	## Auxiliary: Populates selectable item buttons in ItemsContainer matching slot and filter.
	if _items_container == null or _active_slot.is_empty():
		return

	for child in _items_container.get_children():
		child.queue_free()

	# 1. Clear Option: Always provide a "(None / Clear)" button at top of list.
	var none_btn := Button.new()
	none_btn.text = "• (None / Clear Desired Target)"
	none_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	none_btn.add_theme_font_size_override("font_size", 12)
	none_btn.pressed.connect(func() -> void:
		_select_desired_item("")
	)
	_items_container.add_child(none_btn)

	# 2. Eligible Items: Retrieve valid items for this slot via domain helper.
	var eligible: Array[ItemDef] = Equipment.get_eligible_items_for_slot(_active_slot)
	var current_desired: String = _colonist.equipment.get_desired_item(_active_slot) if (_colonist != null and _colonist.equipment != null) else ""
	var clean_filter: String = filter_text.strip_edges().to_lower()

	for def: ItemDef in eligible:
		if def == null:
			continue
		var iname: String = def.resource_name if def.resource_name != "" else def.id
		if not clean_filter.is_empty():
			var matches_name: bool = iname.to_lower().contains(clean_filter)
			var matches_id: bool = def.id.to_lower().contains(clean_filter)
			var matches_tag: bool = false
			for tag: String in def.tags:
				if tag.to_lower().contains(clean_filter):
					matches_tag = true
					break
			if not (matches_name or matches_id or matches_tag):
				continue

		var is_selected: bool = (def.id == current_desired)
		var item_btn := Button.new()
		var checkmark: String = "✓ " if is_selected else "  "
		var tags_str: String = "[%s]" % ", ".join(def.tags) if not def.tags.is_empty() else ""
		item_btn.text = "%s%s %s (%.1f kg)" % [checkmark, iname, tags_str, def.weight]
		item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_btn.add_theme_font_size_override("font_size", 12)
		if is_selected:
			item_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3, 1.0))

		var item_id: String = def.id
		item_btn.pressed.connect(func() -> void:
			_select_desired_item(item_id)
		)
		_items_container.add_child(item_btn)


func _select_desired_item(item_id: String) -> void:
	## Auxiliary: Applies the chosen desired item ID to the active slot and refreshes UI.
	if _colonist == null or _colonist.equipment == null or _active_slot.is_empty():
		return

	_colonist.equipment.set_desired_item(_active_slot, item_id)
	if _row_instances.has(_active_slot):
		_row_instances[_active_slot].refresh()

	# 1. Close Picker: Close picker after selection.
	_close_picker()
