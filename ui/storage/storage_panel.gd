extends Control
## Transfer panel between a player inventory and a storage container's
## StorageInventory. Two scrollable columns; clicking a row moves one whole
## stack across (source.transfer_to(dest, item_id, count)). Closes on Esc or
## the Close button, and re-captures the mouse on close.
##
## Lifecycle: instantiated by OpenStorageAction, mounted on a CanvasLayer,
## destroyed on close. Row rendering mirrors hud.gd's _refresh_inventory.

signal closed()

@onready var _title_label: Label = $Panel/VBox/Header/TitleLabel
@onready var _close_button: Button = $Panel/VBox/Header/CloseButton
@onready var _player_weight: Label = $Panel/VBox/Body/PlayerColumn/PlayerHeader/PlayerWeight
@onready var _player_list: VBoxContainer = $Panel/VBox/Body/PlayerColumn/PlayerScroll/PlayerList
@onready var _storage_weight: Label = $Panel/VBox/Body/StorageColumn/StorageHeader/StorageWeight
@onready var _storage_list: VBoxContainer = $Panel/VBox/Body/StorageColumn/StorageScroll/StorageList

var _player_inv: Inventory = null
var _storage_inv: Inventory = null


func setup(player_inv: Inventory, storage_inv: Inventory) -> void:
	_player_inv = player_inv
	_storage_inv = storage_inv
	# Defer until the node is in the tree so @onready has resolved.
	if not is_node_ready():
		ready.connect(_initial_refresh, CONNECT_ONE_SHOT)
	else:
		_initial_refresh()


func _initial_refresh() -> void:
	var tlabel = _storage_inv.get_parent().get("label")
	_title_label.text = tlabel if tlabel != null and tlabel != "" else "Storage"
	_player_inv.inventory_changed.connect(_refresh)
	_storage_inv.inventory_changed.connect(_refresh)
	_close_button.pressed.connect(close)
	_refresh()


func _refresh(_changed_inv: Inventory = null) -> void:
	if _player_inv == null or _storage_inv == null:
		return
	_player_weight.text = "%.1f / %.0f" % [_player_inv.current_weight(), _player_inv.capacity]
	_storage_weight.text = "%.1f / %.0f" % [_storage_inv.current_weight(), _storage_inv.capacity]
	_rebuild_list(_player_list, _player_inv, _storage_inv)
	_rebuild_list(_storage_list, _storage_inv, _player_inv)


## Rebuild `list` from `source`, clicking a row transferring to `dest`.
func _rebuild_list(list: VBoxContainer, source: Inventory, dest: Inventory) -> void:
	for child in list.get_children():
		child.queue_free()
	for item_id in source.items:
		var count: int = source.items[item_id]
		var def: ItemDef = ItemDB.get_def(item_id)
		if def == null:
			continue
		var row := Button.new()
		row.text = "%s  x%d  (%.1f kg)" % [
			def.resource_name if def.resource_name != "" else item_id,
			count, def.weight * count,
		]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.flat = true
		# Bind by value — `item_id`/`count` change per iteration.
		row.pressed.connect(func() -> void:
			source.transfer_to(dest, item_id, count)
		)
		list.add_child(row)


func close() -> void:
	closed.emit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
