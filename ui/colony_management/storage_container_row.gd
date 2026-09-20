extends PanelContainer
class_name StorageContainerRow
## A single storage container card in the Storage screen of Colony Management.
## Displays container label, world position, priority and accepted items, total
## stored weight / capacity, and a breakdown of item stacks inside. Redraws from the
## container's inventory_changed signal (one coalesced rebuild per frame), not a timer.

const _ITEM_ROW_SCENE: PackedScene = preload("res://ui/shared/item_row.tscn")

@onready var _container_name_label: Label = %ContainerNameLabel
@onready var _filter_label: Label = %FilterLabel
@onready var _weight_label: Label = %WeightLabel
@onready var _weight_progress_bar: ProgressBar = %WeightProgressBar
@onready var _item_list: VBoxContainer = %ItemList

var _furniture: Furniture = null
var _refresh_pending: bool = false


func setup(furniture: Furniture) -> void:
	_furniture = furniture
	if not is_node_ready():
		ready.connect(_initial_refresh, CONNECT_ONE_SHOT)
	else:
		_initial_refresh()


func _initial_refresh() -> void:
	if _furniture == null or not is_instance_valid(_furniture):
		return

	_update_header()
	_refresh_inventory()

	# Any deposit, withdrawal, priority or filter change redraws the card.
	var inv: StorageInventory = _furniture.get_node_or_null("StorageInventory") as StorageInventory
	if inv != null:
		inv.inventory_changed.connect(_request_refresh)


func _update_header() -> void:
	if _furniture == null or not is_instance_valid(_furniture):
		return
	var label_text := _furniture.label if (_furniture != null and _furniture.label != "") else "Storage Container"
	var pos := Vector3i(int(floor(_furniture.global_position.x)), int(floor(_furniture.global_position.y)), int(floor(_furniture.global_position.z)))
	_container_name_label.text = "%s  @ (%d, %d, %d)" % [label_text, pos.x, pos.y, pos.z]


func _request_refresh() -> void:
	## Auxiliary: Queues one redraw for the end of the frame, however many changes fired (hauls come in bursts).
	if _refresh_pending:
		return
	_refresh_pending = true
	_refresh_inventory.call_deferred()


func _refresh_inventory() -> void:
	_refresh_pending = false
	if _furniture == null or not is_instance_valid(_furniture) or _item_list == null:
		return

	# Detach before freeing so a same-frame redraw never lays out old and new rows together.
	for child in _item_list.get_children():
		_item_list.remove_child(child)
		child.queue_free()

	var inv: StorageInventory = _furniture.get_node_or_null("StorageInventory") as StorageInventory
	if inv == null:
		_filter_label.text = ""
		_weight_label.text = "Capacity: N/A"
		_weight_progress_bar.value = 0.0
		var empty_lbl := Label.new()
		empty_lbl.text = "No storage inventory component"
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		_item_list.add_child(empty_lbl)
		return

	_filter_label.text = StorageSummary.describe(inv)
	var current_wt := inv.current_weight()
	var cap := inv.capacity
	_weight_label.text = "Stored Weight: %.1f / %.1f kg" % [current_wt, cap]

	var ratio := current_wt / maxf(cap, 0.001)
	_weight_progress_bar.value = clampf(ratio * 100.0, 0.0, 100.0)

	if inv.items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Empty (No stored items)"
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		_item_list.add_child(empty_lbl)
		return

	for item_id in ItemStackOrder.sorted_item_ids(inv.items):
		var def: ItemDef = ItemDB.get_def(item_id)
		if def == null:
			continue
		var stack_row := _ITEM_ROW_SCENE.instantiate() as ItemRow
		_item_list.add_child(stack_row)
		stack_row.set_compact(true)
		stack_row.setup(def, int(inv.items[item_id]))
