class_name StorageFilterPanel
extends Control
## Modal UI panel for configuring allowed_item_ids on storage containers (crates, shelves).
##
## Left section: search and filter all registered items in ItemDB with checkboxes.
## Right section: shows all currently allowed items with quick removal checkboxes.
## When allowed_item_ids is empty, the storage container is unrestricted and accepts all items.

signal closed()

@onready var _title_label: Label = %TitleLabel
@onready var _close_button: Button = %CloseButton
@onready var _search_edit: LineEdit = %SearchEdit
@onready var _count_label: Label = %CountLabel
@onready var _all_items_list: VBoxContainer = %AllItemsList
@onready var _clear_button: Button = %ClearButton
@onready var _priority_option: OptionButton = %PriorityOption
@onready var _status_label: Label = %StatusLabel
@onready var _allowed_items_list: VBoxContainer = %AllowedItemsList
@onready var _done_button: Button = %DoneButton

var _furniture: Furniture = null
var _storage_inv: StorageInventory = null
var _all_defs: Array[ItemDef] = []
var _left_checkboxes_by_id: Dictionary = {} # item_id (String) -> CheckBox


# =================
# Primary Functions
# =================

func _ready() -> void:
	# 1. Modal Registration: Register with UiGate to capture cursor and block gameplay inputs.
	UiGate.open_modal(self)
	
	# 2. Event Connections: Wire UI buttons and search input listeners.
	_connect_ui_signals()
	
	# 3. Initial Population: Populate item definitions from ItemDB.
	_load_all_item_defs()
	
	# 4. View Rendering: Render left item list and right allowed list.
	_refresh_all_views()
	
	if _search_edit != null:
		_search_edit.grab_focus()


func _exit_tree() -> void:
	# 1. Modal Deregistration: Deregister with UiGate on panel teardown.
	UiGate.close_modal(self)


func setup(furniture: Furniture, storage_inv: StorageInventory) -> void:
	_furniture = furniture
	_storage_inv = storage_inv
	if is_node_ready():
		# 1. Header Refresh: Updates the panel title with container label.
		_update_title_label()
		# 2. View Refresh: Re-renders the list contents with new inventory ref.
		_refresh_all_views()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func filter_items(query: String) -> void:
	var q := query.strip_edges().to_lower()
	var visible_count := 0
	
	for child in _all_items_list.get_children():
		var row := child as Control
		if row == null:
			continue
		var item_id: String = row.get_meta("item_id", "")
		var def: ItemDef = ItemDB.get_def(item_id) if ItemDB != null else null
		
		# 1. Score Calculation: Match item ID, display name, and tags against search query.
		var matches := _does_item_match_query(q, item_id, def)
		row.visible = matches
		if matches:
			visible_count += 1
			
	# 2. Count Label Update: Displays filtered item counts.
	_update_count_label(visible_count, _all_defs.size())


# ===================
# Auxiliary Functions
# ===================

func _connect_ui_signals() -> void:
	## Auxiliary: Connects user action buttons and search box signals.
	if _close_button != null:
		_close_button.pressed.connect(close)
	if _done_button != null:
		_done_button.pressed.connect(close)
	if _clear_button != null:
		_clear_button.pressed.connect(_on_clear_pressed)
	if _search_edit != null:
		_search_edit.text_changed.connect(_on_search_changed)
	if _priority_option != null:
		# 1. Priority Dropdown Setup: Populate 1-5 priority options.
		_setup_priority_options()
		_priority_option.item_selected.connect(_on_priority_selected)


func _setup_priority_options() -> void:
	## Auxiliary: Populates the Priority OptionButton with 1-5 levels.
	if _priority_option == null:
		return
	_priority_option.clear()
	_priority_option.add_item("1 - Lowest Priority", 1)
	_priority_option.add_item("2 - Low Priority", 2)
	_priority_option.add_item("3 - Normal Priority", 3)
	_priority_option.add_item("4 - High Priority", 4)
	_priority_option.add_item("5 - Highest Priority", 5)


func _load_all_item_defs() -> void:
	## Auxiliary: Loads all item definitions from ItemDB sorted alphabetically.
	_all_defs.clear()
	if ItemDB != null:
		_all_defs = ItemDB.get_all_defs()
	_all_defs.sort_custom(func(a: ItemDef, b: ItemDef) -> bool:
		return a.id.to_lower() < b.id.to_lower()
	)


func _update_title_label() -> void:
	## Auxiliary: Formats the header label with the container name.
	if _title_label == null:
		return
	var container_name := "Storage"
	if _furniture != null:
		var tlabel = _furniture.get("label")
		if tlabel != null and str(tlabel) != "":
			container_name = str(tlabel)
	_title_label.text = "Configure Filter - %s" % container_name


func _refresh_all_views() -> void:
	## Auxiliary: Refreshes title, left filterable list, right allowed list, and priority dropdown.
	_update_title_label()
	
	# 1. Priority Selection Refresh: Syncs OptionButton with current inventory priority.
	_refresh_priority_selection()
	
	# 2. Left List Population: Builds all item rows.
	_build_all_items_list()
	
	# 3. Right List Population: Builds whitelisted allowed items.
	_refresh_allowed_list()


func _refresh_priority_selection() -> void:
	## Auxiliary: Sets selected item on priority dropdown based on storage inventory.
	if _priority_option == null or _storage_inv == null:
		return
	var target_index := clampi(_storage_inv.priority - 1, 0, 4)
	if _priority_option.selected != target_index:
		_priority_option.select(target_index)


func _on_priority_selected(index: int) -> void:
	## Auxiliary: Handles player changing priority level via dropdown.
	if _storage_inv == null:
		return
	var new_priority := index + 1
	_storage_inv.set_priority(new_priority)


func _build_all_items_list() -> void:
	## Auxiliary: Constructs the left-side list containing all registered items.
	if _all_items_list == null:
		return
	for child in _all_items_list.get_children():
		child.queue_free()
	_left_checkboxes_by_id.clear()

	for def in _all_defs:
		# 1. Row Construction: Build row container with checkbox and label.
		var row := _create_all_item_row(def)
		_all_items_list.add_child(row)

	var query := _search_edit.text if _search_edit != null else ""
	# 2. Filtering Pass: Filter newly built items based on current search term.
	filter_items(query)


func _create_all_item_row(def: ItemDef) -> HBoxContainer:
	## Auxiliary: Creates an HBoxContainer row representing an item definition.
	var row := HBoxContainer.new()
	row.set_meta("item_id", def.id)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var is_allowed := _is_item_in_whitelist(def.id)

	var cb := CheckBox.new()
	cb.button_pressed = is_allowed
	cb.toggled.connect(func(pressed: bool) -> void:
		_on_item_toggled(def.id, pressed)
	)
	row.add_child(cb)
	_left_checkboxes_by_id[def.id] = cb

	if def.icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = def.icon
		icon_rect.custom_minimum_size = Vector2(24, 24)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon_rect)

	var name_label := Label.new()
	var display_name := def.resource_name if def.resource_name != "" else def.id
	name_label.text = "%s (%s)" % [display_name, def.id]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var weight_label := Label.new()
	weight_label.text = "%.1f kg" % def.weight
	row.add_child(weight_label)

	return row


func _refresh_allowed_list() -> void:
	## Auxiliary: Rebuilds the right-side list containing only allowed whitelisted items.
	if _allowed_items_list == null:
		return
	for child in _allowed_items_list.get_children():
		child.queue_free()

	var allowed_ids := _get_allowed_ids()
	
	# 1. Status Update: Updates description label explaining current storage filter state.
	_update_allowed_status_label(allowed_ids.size())

	if allowed_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "All items allowed (no filter active).\nCheck items on the left to restrict storage."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_allowed_items_list.add_child(empty_label)
		return

	for item_id in allowed_ids:
		var def := ItemDB.get_def(item_id) if ItemDB != null else null
		# 2. Row Construction: Creates allowed item row with checkbox/remove button.
		var row := _create_allowed_item_row(item_id, def)
		_allowed_items_list.add_child(row)


func _create_allowed_item_row(item_id: String, def: ItemDef) -> HBoxContainer:
	## Auxiliary: Creates an HBoxContainer row representing an allowed whitelist entry.
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cb := CheckBox.new()
	cb.button_pressed = true
	cb.toggled.connect(func(pressed: bool) -> void:
		if not pressed:
			_on_item_toggled(item_id, false)
	)
	row.add_child(cb)

	if def != null and def.icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = def.icon
		icon_rect.custom_minimum_size = Vector2(24, 24)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon_rect)

	var name_label := Label.new()
	var display_name := def.resource_name if (def != null and def.resource_name != "") else item_id
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var remove_btn := Button.new()
	remove_btn.text = "X"
	remove_btn.flat = true
	remove_btn.pressed.connect(func() -> void:
		_on_item_toggled(item_id, false)
	)
	row.add_child(remove_btn)

	return row


func _on_item_toggled(item_id: String, pressed: bool) -> void:
	## Auxiliary: Handles checkbox toggles on either left or right section.
	if _storage_inv == null:
		return
	_storage_inv.set_item_allowed(item_id, pressed)
	
	# 1. Left Checkbox Sync: Updates left-side checkbox state if present.
	if _left_checkboxes_by_id.has(item_id):
		var cb: CheckBox = _left_checkboxes_by_id[item_id]
		if is_instance_valid(cb) and cb.button_pressed != pressed:
			cb.set_pressed_no_signal(pressed)

	# 2. Right List Refresh: Re-renders the right-side list to match updated whitelist.
	_refresh_allowed_list()


func _on_clear_pressed() -> void:
	## Auxiliary: Clears all items from the whitelist so the container accepts everything.
	if _storage_inv == null:
		return
	_storage_inv.clear_allowed_items()
	
	# 1. Left Checkboxes Reset: Uncheck all left-side checkboxes without triggering signals.
	for cb: CheckBox in _left_checkboxes_by_id.values():
		if is_instance_valid(cb):
			cb.set_pressed_no_signal(false)

	# 2. Right List Refresh: Re-renders right section in unrestricted state.
	_refresh_allowed_list()


func _on_search_changed(query: String) -> void:
	## Auxiliary: Invoked when the player types into the search box.
	filter_items(query)


func _does_item_match_query(q: String, item_id: String, def: ItemDef) -> bool:
	## Auxiliary: Checks if an item matches the current search query.
	if q.is_empty():
		return true
	if item_id.to_lower().find(q) != -1:
		return true
	if def != null:
		if def.resource_name.to_lower().find(q) != -1:
			return true
		for tag in def.tags:
			if tag.to_lower().find(q) != -1:
				return true
	return false


func _is_item_in_whitelist(item_id: String) -> bool:
	## Auxiliary: Checks if an item ID is in the storage inventory's allowed whitelist.
	if _storage_inv == null:
		return false
	return _storage_inv.allowed_item_ids.has(item_id)


func _get_allowed_ids() -> Array[String]:
	## Auxiliary: Returns the current allowed item IDs from the storage inventory.
	if _storage_inv == null:
		return []
	return _storage_inv.allowed_item_ids


func _update_count_label(visible_count: int, total_count: int) -> void:
	## Auxiliary: Updates the item count label in the left section.
	if _count_label != null:
		_count_label.text = "Showing %d / %d items" % [visible_count, total_count]


func _update_allowed_status_label(allowed_count: int) -> void:
	## Auxiliary: Updates the status label in the right section.
	if _status_label == null:
		return
	if allowed_count == 0:
		_status_label.text = "Status: Unrestricted (accepts all items)"
	else:
		_status_label.text = "Status: Restricted (%d item%s allowed)" % [
			allowed_count,
			"" if allowed_count == 1 else "s"
		]
