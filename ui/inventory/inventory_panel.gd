class_name InventoryPanel
extends PanelContainer
## Player inventory side panel, toggled with I: the Equipped strip (one row per
## occupied slot, each with Unequip) above the carried stacks (Equip / Eat / Drop
## / Drop All).
##
## Equipped gear lives in Equipment, not the carry inventory (Equipment.
## equip_from_inventory MOVES it), so it appears only in the strip and never in
## the carried list. The panel owns its I / Esc handling and its UiGate
## registration (persistent panel: registered in open/close, not _ready/_exit_tree).
## It only rebuilds while open, and coalesces the several signals one equip fires
## into a single deferred rebuild.

const _ITEM_ROW_SCENE: PackedScene = preload("res://ui/inventory/inventory_item_row.tscn")
const _SLOT_ROW_SCENE: PackedScene = preload("res://ui/inventory/equipped_slot_row.tscn")

## Strip order: hands first, then the worn slots.
const _SLOT_ORDER: Array[String] = [
	Equipment.SLOT_MAIN_HAND, Equipment.SLOT_HOLSTER, Equipment.SLOT_OFF_HAND,
	Equipment.SLOT_HEAD, Equipment.SLOT_TORSO, Equipment.SLOT_LEGS,
	Equipment.SLOT_FEET, Equipment.SLOT_BACK,
]

@onready var _weight_label: Label = %WeightLabel
@onready var _equipped_list: VBoxContainer = %EquippedList
@onready var _equipped_empty_label: Label = %EquippedEmptyLabel
@onready var _item_list: VBoxContainer = %ItemList
@onready var _status_label: Label = %StatusLabel

var _player: Player = null
var _open: bool = false
var _refresh_pending: bool = false


# =================
# Primary Functions
# =================

## Called by the HUD once the player's inventory and equipment exist.
func setup(player: Player) -> void:
	_player = player
	# 1. Change Wiring: Any carry or equipment change while open rebuilds the lists.
	_player.inventory.inventory_changed.connect(_request_refresh)
	if _player.equipment != null:
		_player.equipment.slot_changed.connect(_on_slot_changed)


func open() -> void:
	if _open or _player == null:
		return
	_open = true
	visible = true
	# 1. Modal Registration: Blocks gameplay input and shows the cursor while open.
	UiGate.open_modal(self)
	# 2. Fresh Start: A stale failure message from the last session must not greet the player.
	_set_status("")
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	UiGate.close_modal(self)


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	# I toggles the inventory, but never on top of another open modal (e.g. a
	# storage panel); closing our own panel is always allowed.
	if event.is_action_pressed("inventory_toggle"):
		if _open or not UiGate.is_input_blocked():
			toggle()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _open:
		close()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _open:
		UiGate.close_modal(self)


## Player-facing reason an equip did nothing; "" for OK. Static and pure so the
## wording is testable without a scene.
static func equip_failure_text(result: Equipment.EquipResult, item_name: String) -> String:
	match result:
		Equipment.EquipResult.NOT_CARRIED:
			return "You aren't carrying %s." % item_name
		Equipment.EquipResult.NO_SLOT:
			return "%s can't be equipped." % item_name
		Equipment.EquipResult.ALREADY_HELD:
			return "You're already holding %s." % item_name
		Equipment.EquipResult.NO_ROOM:
			return "No room in your pack to stow what you're holding."
	return ""


# ===================
# Auxiliary Functions
# ===================

func _on_slot_changed(_slot_id: String, _item: ItemDef) -> void:
	## Auxiliary: Adapts Equipment.slot_changed's payload to the argument-free refresh request.
	_request_refresh()


func _request_refresh() -> void:
	## Auxiliary: Queues one rebuild for the end of the frame, however many changes fired, and none while closed.
	if not _open or _refresh_pending:
		return
	_refresh_pending = true
	_refresh.call_deferred()


func _refresh() -> void:
	## Auxiliary: Rebuilds the weight header, the Equipped strip and the carried list.
	_refresh_pending = false
	if not _open or _player == null:
		return
	# 1. Weight Header: Current load against capacity.
	_update_weight_label()
	# 2. Equipped Strip: One row per occupied slot, or the placeholder when none.
	_rebuild_equipped_strip()
	# 3. Carried List: One row per stack still in the inventory.
	_rebuild_item_list()


func _update_weight_label() -> void:
	## Auxiliary: Shows "current / capacity" carry weight.
	var inventory: Inventory = _player.inventory
	_weight_label.text = "%.1f / %.0f" % [inventory.current_weight(), inventory.capacity]


func _rebuild_equipped_strip() -> void:
	## Auxiliary: Recreates the Equipped rows in slot order and toggles the empty placeholder.
	var focus_token: Dictionary = RowFocus.capture(_equipped_list)
	_clear_children(_equipped_list)
	if _player.equipment != null:
		for slot_id: String in _SLOT_ORDER:
			var held: ItemDef = _player.equipment.get_item(slot_id)
			if held != null:
				_add_slot_row(slot_id, held)
	_equipped_empty_label.visible = _equipped_list.get_child_count() == 0
	RowFocus.restore(_equipped_list, focus_token)


func _rebuild_item_list() -> void:
	## Auxiliary: Recreates one row per carried stack whose ItemDef resolves, in stable display order.
	var focus_token: Dictionary = RowFocus.capture(_item_list)
	_clear_children(_item_list)
	for item_id: String in ItemStackOrder.sorted_item_ids(_player.inventory.items):
		var def: ItemDef = ItemDB.get_def(item_id)
		if def != null:
			_add_item_row(def, _player.inventory.items[item_id])
	RowFocus.restore(_item_list, focus_token)


func _clear_children(container: Container) -> void:
	## Auxiliary: Detaches then frees the rows, so the container never lays out old and new rows together.
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_slot_row(slot_id: String, held: ItemDef) -> void:
	## Auxiliary: Mounts one Equipped row and routes its Unequip intent to the panel.
	var row := _SLOT_ROW_SCENE.instantiate() as EquippedSlotRow
	_equipped_list.add_child(row)
	row.set_meta(RowFocus.KEY_META, slot_id)
	row.setup(slot_id, held)
	row.unequip_pressed.connect(_on_unequip_requested)


func _add_item_row(def: ItemDef, count: int) -> void:
	## Auxiliary: Mounts one carried-stack row and routes its action intents to the panel.
	var row := _ITEM_ROW_SCENE.instantiate() as InventoryItemRow
	_item_list.add_child(row)
	row.set_meta(RowFocus.KEY_META, def.id)
	row.setup_stack(def, count, _can_equip(def))
	row.equip_pressed.connect(_on_equip_requested.bind(def))
	row.eat_pressed.connect(_on_eat_requested.bind(def.id))
	row.drop_pressed.connect(_on_drop_requested.bind(def.id))


func _can_equip(def: ItemDef) -> bool:
	## Auxiliary: Equip is offered when some slot accepts the item (tools, weapons and apparel alike).
	return _player.equipment != null and not _player.equipment.resolve_equip_slot(def).is_empty()


func _on_equip_requested(def: ItemDef) -> void:
	## Auxiliary: Equips the item and explains a refusal instead of failing silently.
	# 1. Equip Attempt: Moves one from the inventory, stowing whatever it displaces.
	var result: Equipment.EquipResult = _player.equip_item(def)
	# 2. Feedback: Clears the message on success, names the reason otherwise.
	_set_status(equip_failure_text(result, def.get_display_name()))


func _on_unequip_requested(slot_id: String) -> void:
	## Auxiliary: Returns the slot's item to the pack, or says the pack has no room.
	var held: ItemDef = _player.equipment.get_item(slot_id)
	if _player.unequip_slot(slot_id):
		_set_status("")
	elif held != null:
		_set_status("No room in your pack for %s." % held.get_display_name())


func _on_eat_requested(item_id: String) -> void:
	## Auxiliary: Eats one unit; the inventory change signal refreshes the list.
	_player.consume_food_item(item_id)


func _on_drop_requested(count: int, item_id: String) -> void:
	## Auxiliary: Drops `count` units into the world; the inventory change signal refreshes the list.
	_player.drop_item(item_id, count)


func _set_status(text: String) -> void:
	## Auxiliary: Shows a one-line message under the lists, hidden when empty.
	_status_label.text = text
	_status_label.visible = not text.is_empty()
