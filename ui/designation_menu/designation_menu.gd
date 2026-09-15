class_name DesignationMenu
extends Control
## Modal menu for orders and area designations (hotkey T).
## Offers one-time flora orders (Remove Plant, Chop Tree, Forage, Cancel Orders)
## and persistent area CRUD with Paint and Erase operations.

signal closed()
signal tool_selected(tool_id: String, target_area_id: String)

@onready var _close_button: Button = %CloseButton
@onready var _remove_plants_button: Button = %RemovePlantsButton
@onready var _chop_trees_button: Button = %ChopTreesButton
@onready var _forage_button: Button = %ForageButton
@onready var _cancel_orders_button: Button = %CancelOrdersButton
@onready var _new_area_button: Button = %NewAreaButton
@onready var _area_list: VBoxContainer = %AreaList
@onready var _no_areas_label: Label = %NoAreasLabel


# =================
# Primary Functions
# =================

func _ready() -> void:
	UiGate.open_modal(self)
	_connect_widget_signals()
	# 1. Area Roster Population: Gathers existing areas and displays interactive rows.
	_populate_areas()


func _exit_tree() -> void:
	UiGate.close_modal(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("area_designation_toggle"):
		get_viewport().set_input_as_handled()
		# 1. Menu Dismissal: Closes the modal without selecting an order.
		close()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_1:
				get_viewport().set_input_as_handled()
				# 1. Order Selection: Dispatches remove plant tool.
				_select_tool("remove_plant")
			KEY_2:
				get_viewport().set_input_as_handled()
				# 1. Order Selection: Dispatches chop tree tool.
				_select_tool("chop_tree")
			KEY_3:
				get_viewport().set_input_as_handled()
				# 1. Order Selection: Dispatches forage tool.
				_select_tool("forage")
			KEY_4:
				get_viewport().set_input_as_handled()
				# 1. Order Selection: Dispatches cancel orders tool.
				_select_tool("cancel_orders")


func close() -> void:
	closed.emit()
	queue_free()


# ===================
# Auxiliary Functions
# ===================

func _connect_widget_signals() -> void:
	## Auxiliary: Wires UI buttons to their corresponding tool selection handlers.
	if _close_button != null:
		_close_button.pressed.connect(close)
	if _remove_plants_button != null:
		_remove_plants_button.pressed.connect(_select_tool.bind("remove_plant", ""))
	if _chop_trees_button != null:
		_chop_trees_button.pressed.connect(_select_tool.bind("chop_tree", ""))
	if _forage_button != null:
		_forage_button.pressed.connect(_select_tool.bind("forage", ""))
	if _cancel_orders_button != null:
		_cancel_orders_button.pressed.connect(_select_tool.bind("cancel_orders", ""))
	if _new_area_button != null:
		_new_area_button.pressed.connect(_select_tool.bind("create_area", ""))


func _populate_areas() -> void:
	## Auxiliary: Populates area list with existing areas and Paint/Erase buttons.
	if _area_list == null:
		return

	for child in _area_list.get_children():
		if child != _no_areas_label:
			_area_list.remove_child(child)
			child.queue_free()

	if Colony == null or Colony.area_manager == null:
		return

	var all_areas: Array[Area] = Colony.area_manager.get_all_areas()
	if all_areas.is_empty():
		if _no_areas_label != null:
			_no_areas_label.visible = true
		return

	if _no_areas_label != null:
		_no_areas_label.visible = false

	for area in all_areas:
		var row := _build_area_row(area)
		_area_list.add_child(row)


func _build_area_row(area: Area) -> HBoxContainer:
	## Auxiliary: Constructs an interactive row for an area with Paint and Erase actions.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box_count := area.boxes.size()
	label.text = "• %s (%d box%s)" % [area.display_name, box_count, "es" if box_count != 1 else ""]
	row.add_child(label)

	var paint_btn := Button.new()
	paint_btn.text = "Paint"
	paint_btn.pressed.connect(_select_tool.bind("paint_area", area.id))
	row.add_child(paint_btn)

	var erase_btn := Button.new()
	erase_btn.text = "Erase"
	erase_btn.pressed.connect(_select_tool.bind("erase_area", area.id))
	row.add_child(erase_btn)

	return row


func _select_tool(tool_id: String, target_area_id: String = "") -> void:
	## Auxiliary: Emits tool selected signal and dismisses the menu.
	EventBus.area_designation_tool_selected.emit(tool_id, target_area_id)
	tool_selected.emit(tool_id, target_area_id)
	queue_free()
