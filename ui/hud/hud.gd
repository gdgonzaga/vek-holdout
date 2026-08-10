extends Control
## Persistent HUD overlay mounted on the HUDLayer (layer=10).
##
## Contains:
##   - Crosshair (center screen)
##   - Interactable name label (below crosshair)
##   - Inventory side panel (left edge, toggled with I)

@onready var _crosshair: TextureRect = $Crosshair
@onready var _interact_label: Label = $InteractLabel
@onready var _inventory_panel: PanelContainer = $InventoryPanel
@onready var _weight_label: Label = $InventoryPanel/VBox/Header/WeightLabel
@onready var _item_list: VBoxContainer = $InventoryPanel/VBox/ScrollContainer/ItemList

var _player: Player = null
var _inventory: Inventory = null
var _inventory_open := false


func _ready() -> void:
	_interact_label.visible = false


## Called by Main after mounting the HUD on the HUDLayer.
func setup(player: Player) -> void:
	_player = player
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


func _on_interactable_changed(component: InteractionComponent) -> void:
	if component == null:
		_interact_label.visible = false
		return
	_interact_label.visible = true
	var target: Node = component.get_parent()
	# Same resolution order as interaction_ui.gd: label > display_name > node name.
	var tlabel = target.get("label")
	if tlabel != null and tlabel != "":
		_interact_label.text = str(tlabel)
	elif component.display_name != "":
		_interact_label.text = component.display_name
	else:
		_interact_label.text = target.name


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
