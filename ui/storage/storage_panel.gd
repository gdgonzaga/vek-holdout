class_name StoragePanel
extends Control
## Transfer panel between a player inventory and a storage container's
## StorageInventory. Two columns of item rows, each with 1 / 10 / All buttons that
## move that many across (source.transfer_to(dest, item_id, count)). A row the
## destination cannot take is dimmed and says why; a status line reports partial or
## failed moves; capacity bars tint when nearly full; the header shows the
## container's priority and filter, with an Options button (configure_requested).
## Closes on Esc, I, E or the Close button.
##
## Lifecycle: instantiated by OpenStorageAction, mounted on a CanvasLayer,
## destroyed on close. Refreshes coalesce into one deferred rebuild per frame.

signal closed()
## Emitted by the Options button. OpenStorageAction opens the filter/priority panel
## on top; this panel stays open and live-updates when the container's rules change.
signal configure_requested()

const _ROW_SCENE: PackedScene = preload("res://ui/storage/storage_item_row.tscn")
const _NEARLY_FULL_RATIO: float = 0.9
const _NEARLY_FULL_TINT: Color = Color(1.0, 0.65, 0.35)
const _PACK_NAME: String = "your pack"

@onready var _title_label: Label = %TitleLabel
@onready var _configure_button: Button = %ConfigureButton
@onready var _close_button: Button = %CloseButton
@onready var _info_label: Label = %InfoLabel
@onready var _player_weight: Label = %PlayerWeight
@onready var _player_bar: ProgressBar = %PlayerBar
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _player_empty: Label = %PlayerEmptyLabel
@onready var _storage_weight: Label = %StorageWeight
@onready var _storage_bar: ProgressBar = %StorageBar
@onready var _storage_list: VBoxContainer = %StorageList
@onready var _storage_empty: Label = %StorageEmptyLabel
@onready var _status_label: Label = %StatusLabel

var _player_inv: Inventory = null
var _storage_inv: Inventory = null
var _container_name: String = "Storage"
var _refresh_pending: bool = false


# =================
# Primary Functions
# =================

func setup(player_inv: Inventory, storage_inv: Inventory) -> void:
	_player_inv = player_inv
	_storage_inv = storage_inv
	# Defer until the node is in the tree so @onready has resolved.
	if not is_node_ready():
		ready.connect(_initial_refresh, CONNECT_ONE_SHOT)
	else:
		_initial_refresh()


func close() -> void:
	closed.emit()
	queue_free()


func _ready() -> void:
	UiGate.open_modal(self)


func _exit_tree() -> void:
	UiGate.close_modal(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc always closes (a panel opened on top consumes it first). I and E also close,
	# but only for the topmost panel, so the options panel's own keys never close this.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif _is_close_key(event) and _is_topmost():
		get_viewport().set_input_as_handled()
		close()


## Fraction of capacity in use, 0..1. A zero-capacity container reads as full once
## it holds anything, so its bar is never misleadingly empty.
static func capacity_ratio(current: float, capacity: float) -> float:
	if capacity <= 0.0:
		return 1.0 if current > 0.0 else 0.0
	return clampf(current / capacity, 0.0, 1.0)


## Why a destination will not take an item: a filter, or no room left.
static func block_reason_text(dest_name: String, item_name: String, dest_allows: bool) -> String:
	if not dest_allows:
		return "%s doesn't accept %s." % [_capitalize_first(dest_name), item_name]
	return "No room in %s." % dest_name


## Status line after a move; "" when all of it moved. `reason` (may be "") explains a shortfall.
static func transfer_status_text(item_name: String, requested: int, moved: int, reason: String) -> String:
	if moved >= requested:
		return ""
	var lead: String = "Couldn't move %s." % item_name
	if moved > 0:
		lead = "Moved %d of %d %s." % [moved, requested, item_name]
	return lead if reason.is_empty() else "%s %s" % [lead, reason]


# ===================
# Auxiliary Functions
# ===================

static func _capitalize_first(text: String) -> String:
	## Auxiliary: Upper-cases only the first letter, leaving the rest ("the Storage Crate" -> "The Storage Crate").
	return text.substr(0, 1).to_upper() + text.substr(1)


func _is_close_key(event: InputEvent) -> bool:
	## Auxiliary: True for the keys that toggle this panel shut (inventory toggle, interact).
	return event.is_action_pressed("inventory_toggle") or event.is_action_pressed("interact")


func _is_topmost() -> bool:
	## Auxiliary: True when no later sibling (a panel opened over this one) sits above it.
	var parent: Node = get_parent()
	return parent == null or parent.get_child(parent.get_child_count() - 1) == self


func _initial_refresh() -> void:
	## Auxiliary: One-time wiring once both inventories and the scene nodes exist, then the first build.
	# 1. Container Name: The furniture's label, or a generic fallback.
	_container_name = _read_container_name()
	_title_label.text = _container_name
	# 2. Change Wiring: Any change to either side rebuilds; a departing container closes the panel.
	_player_inv.inventory_changed.connect(_request_refresh)
	_storage_inv.inventory_changed.connect(_request_refresh)
	_storage_inv.tree_exiting.connect(close, CONNECT_ONE_SHOT)
	_close_button.pressed.connect(close)
	_configure_button.pressed.connect(func() -> void: configure_requested.emit())
	_configure_button.visible = _storage_inv is StorageInventory
	# 3. First Build: Synchronous so the panel is complete the frame it opens.
	_refresh()


func _read_container_name() -> String:
	## Auxiliary: The container furniture's label ("Storage" when it has none).
	var parent: Node = _storage_inv.get_parent()
	var label: Variant = parent.get("label") if parent != null else null
	return str(label) if label != null and str(label) != "" else "Storage"


func _request_refresh() -> void:
	## Auxiliary: Queues one rebuild for the end of the frame, however many signals fired.
	if _refresh_pending:
		return
	_refresh_pending = true
	_refresh.call_deferred()


func _refresh() -> void:
	## Auxiliary: Rebuilds the header, both capacity bars and both item lists.
	_refresh_pending = false
	if not is_instance_valid(_player_inv) or not is_instance_valid(_storage_inv):
		return
	# 1. Header: Priority and accepted items of the container.
	_update_info_label()
	# 2. Capacity: Weight text and bar for each side.
	_update_capacity(_player_inv, _player_weight, _player_bar)
	_update_capacity(_storage_inv, _storage_weight, _storage_bar)
	# 3. Item Lists: Each row moves toward the other side.
	_rebuild_list(_player_list, _player_empty, _player_inv, _storage_inv, "the " + _container_name)
	_rebuild_list(_storage_list, _storage_empty, _storage_inv, _player_inv, _PACK_NAME)


func _update_info_label() -> void:
	## Auxiliary: Shows the container's priority and filter (only meaningful for a StorageInventory).
	var storage: StorageInventory = _storage_inv as StorageInventory
	_info_label.visible = storage != null
	_info_label.text = StorageSummary.describe(storage) if storage != null else ""


func _update_capacity(inventory: Inventory, weight_label: Label, bar: ProgressBar) -> void:
	## Auxiliary: "current / capacity" text plus a bar that tints when nearly full.
	var current: float = inventory.current_weight()
	weight_label.text = "%.1f / %.0f" % [current, inventory.capacity]
	var ratio: float = capacity_ratio(current, inventory.capacity)
	bar.value = ratio * 100.0
	bar.modulate = _NEARLY_FULL_TINT if ratio >= _NEARLY_FULL_RATIO else Color.WHITE


func _rebuild_list(list: VBoxContainer, empty_label: Label, source: Inventory, dest: Inventory, dest_name: String) -> void:
	## Auxiliary: Recreates one row per stack of `source`, each moving toward `dest`, in stable display order.
	# 1. Focus Note: Which button had keyboard focus, so the rebuild does not drop it.
	var focus_token: Dictionary = RowFocus.capture(list)
	_clear_children(list)
	for item_id: String in ItemStackOrder.sorted_item_ids(source.items):
		var def: ItemDef = ItemDB.get_def(item_id)
		if def != null:
			_add_row(list, def, source, dest, dest_name)
	empty_label.visible = list.get_child_count() == 0
	# 2. Focus Restore: Back onto the same button of the same item (or its neighbour if it left).
	RowFocus.restore(list, focus_token)


func _clear_children(container: Container) -> void:
	## Auxiliary: Detaches then frees the rows, so old and new rows are never laid out together.
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_row(list: VBoxContainer, def: ItemDef, source: Inventory, dest: Inventory, dest_name: String) -> void:
	## Auxiliary: Mounts one row and routes its move intent to the transfer.
	var count: int = source.items[def.id]
	var movable: int = mini(count, dest.max_addable(def.id))
	var row := _ROW_SCENE.instantiate() as StorageItemRow
	list.add_child(row)
	row.set_meta(RowFocus.KEY_META, def.id)
	row.setup_transfer(def, count, movable, _block_reason(dest, def, dest_name))
	# Bind by value: def, source, dest and dest_name differ per row and per column.
	row.move_requested.connect(_on_move_requested.bind(def, source, dest, dest_name))


func _block_reason(dest: Inventory, def: ItemDef, dest_name: String) -> String:
	## Auxiliary: "" while dest can still take some of this item, else why it cannot.
	if dest.max_addable(def.id) > 0:
		return ""
	return block_reason_text(dest_name, def.get_display_name(), dest.is_item_allowed(def.id))


func _on_move_requested(count: int, def: ItemDef, source: Inventory, dest: Inventory, dest_name: String) -> void:
	## Auxiliary: Moves up to `count`, then says so if it could not all go.
	# 1. Transfer: Capped by what source holds and dest accepts; returns the units that stayed behind.
	var moved: int = count - source.transfer_to(dest, def.id, count)
	# 2. Feedback: Silent on a full move, otherwise the shortfall and (if dest is now blocked) why.
	var reason: String = _block_reason(dest, def, dest_name) if moved < count else ""
	_set_status(transfer_status_text(def.get_display_name(), count, moved, reason))


func _set_status(text: String) -> void:
	## Auxiliary: Shows a one-line message under the lists, hidden when empty.
	_status_label.text = text
	_status_label.visible = not text.is_empty()
