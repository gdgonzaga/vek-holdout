extends Control
## Persistent HUD overlay mounted on the HUDLayer (layer=10).
##
## Contains:
##   - Crosshair (center screen)
##   - Interactable label (name + default action hint, below crosshair)
##   - Inventory side panel (left edge, toggled with I)
##
## Handles quick-tap vs long-press for the interact key (E):
##   - Quick tap (< 0.3s): executes the first action option on the targeted
##     interactable furniture.
##   - Long press (≥ 0.3s): opens the full action menu.

const _HOLD_THRESHOLD := 0.3
const _PLACEMENT_TEXT := "LMB: place    RMB: remove\nWheel: rotate    R: cycle axis\nB: back"
const _MENU_TEXT := "Click an item to place\nB: cancel"

@onready var _crosshair: TextureRect = $Crosshair
@onready var _instructions: Label = $Instructions
@onready var _interact_display: Control = $InteractLabel
@onready var _inventory_panel: PanelContainer = $InventoryPanel
@onready var _weight_label: Label = $InventoryPanel/VBox/Header/WeightLabel
@onready var _item_list: VBoxContainer = $InventoryPanel/VBox/ScrollContainer/ItemList

var _player: Player = null
var _input_component: InputComponent = null
var _inventory: Inventory = null
var _inventory_open := false

var _hold_timer := 0.0
var _holding_interact := false


func _ready() -> void:
	pass


## Called by Main after mounting the HUD on the HUDLayer.
func setup(player: Player) -> void:
	_player = player
	_input_component = player.get_node_or_null("InputComponent") as InputComponent
	if _player.inventory != null:
		_wire_signals()
	else:
		_player.ready.connect(_on_player_ready)


func _on_player_ready() -> void:
	_player.ready.disconnect(_on_player_ready)
	_wire_signals()


func _wire_signals() -> void:
	_inventory = _player.inventory
	_player.interactable_changed.connect(_on_interactable_changed)
	_inventory.inventory_changed.connect(_refresh_inventory)
	# Connect to InputComponent's interact press/release for hold detection.
	if _input_component != null:
		_input_component.interact_pressed.connect(_on_interact_pressed)
		_input_component.interact_released.connect(_on_interact_released)
	# Blueprint mode toggles the crosshair (overview.md expects this listener):
	# the build ghost replaces the crosshair while placing an item.
	EventBus.blueprint_mode_toggled.connect(_on_blueprint_mode_toggled)
	# Build menu visibility drives the Instructions label for the menu state.
	EventBus.build_menu_toggled.connect(_on_build_menu_toggled)


func _on_blueprint_mode_toggled(active: bool) -> void:
	_crosshair.visible = not active
	if active:
		_instructions.text = _PLACEMENT_TEXT
	_instructions.visible = active


func _on_build_menu_toggled(open: bool) -> void:
	if open:
		_instructions.text = _MENU_TEXT
	_instructions.visible = open


func _on_interactable_changed(component: InteractionComponent) -> void:
	_interact_display.update_display(component, _player)


func _process(delta: float) -> void:
	if _holding_interact:
		_hold_timer += delta
		if _hold_timer >= _HOLD_THRESHOLD:
			_holding_interact = false
			_hold_timer = 0.0
			_player.open_interaction_menu()


func _on_interact_pressed() -> void:
	if _inventory_open:
		return
	_holding_interact = true
	_hold_timer = 0.0


func _on_interact_released() -> void:
	if _inventory_open:
		return
	if _holding_interact:
		# Released before threshold — quick tap, execute default action.
		_holding_interact = false
		_hold_timer = 0.0
		_player.execute_default_action()
	else:
		# Long-press already fired (menu opening handled in _process).
		_holding_interact = false
		_hold_timer = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_toggle"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _inventory_open:
		_close_inventory()
		get_viewport().set_input_as_handled()


func _toggle_inventory() -> void:
	if _inventory_open:
		_close_inventory()
	else:
		_open_inventory()


func _open_inventory() -> void:
	_inventory_open = true
	_inventory_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_inventory()


func _close_inventory() -> void:
	_inventory_open = false
	_inventory_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_inventory() -> void:
	if _inventory == null:
		return
	# Update weight display.
	_weight_label.text = "%.1f / %.0f" % [_inventory.current_weight(), _inventory.capacity]
	# Rebuild item rows.
	for child in _item_list.get_children():
		child.queue_free()
	for item_id in _inventory.items:
		var count: int = _inventory.items[item_id]
		var def: ItemDef = ItemDB.get_def(item_id)
		if def == null:
			continue
		var row := HBoxContainer.new()
		# Icon.
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = def.icon
		row.add_child(icon)
		# Name.
		var name_label := Label.new()
		name_label.text = def.resource_name if def.resource_name != "" else item_id
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		# Count.
		var count_label := Label.new()
		count_label.text = str(count)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(count_label)
		# Stack weight.
		var weight_label := Label.new()
		weight_label.text = "%.1f" % (def.weight * count)
		weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(weight_label)
		_item_list.add_child(row)
