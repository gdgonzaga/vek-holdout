extends PanelContainer
class_name StorageContainerRow
## A single storage container card in the Storage screen of Colony Management.
## Displays container label, world position, total stored weight / capacity,
## and a breakdown of item stacks inside.

@onready var _container_name_label: Label = %ContainerNameLabel
@onready var _weight_label: Label = %WeightLabel
@onready var _weight_progress_bar: ProgressBar = %WeightProgressBar
@onready var _item_list: VBoxContainer = %ItemList

var _furniture: Furniture = null
var _poll_timer: Timer = null


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

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.5
	_poll_timer.timeout.connect(_refresh_inventory)
	add_child(_poll_timer)
	_poll_timer.start()


func _update_header() -> void:
	if _furniture == null or not is_instance_valid(_furniture):
		return
	var label_text := _furniture.label if (_furniture != null and _furniture.label != "") else "Storage Container"
	var pos := Vector3i(int(floor(_furniture.global_position.x)), int(floor(_furniture.global_position.y)), int(floor(_furniture.global_position.z)))
	_container_name_label.text = "%s  @ (%d, %d, %d)" % [label_text, pos.x, pos.y, pos.z]


func _refresh_inventory() -> void:
	if _furniture == null or not is_instance_valid(_furniture) or _item_list == null:
		return

	for child in _item_list.get_children():
		child.queue_free()

	var inv: StorageInventory = _furniture.get_node_or_null("StorageInventory") as StorageInventory
	if inv == null:
		_weight_label.text = "Capacity: N/A"
		_weight_progress_bar.value = 0.0
		var empty_lbl := Label.new()
		empty_lbl.text = "No storage inventory component"
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		_item_list.add_child(empty_lbl)
		return

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

	for item_id in inv.items:
		var count: int = inv.items[item_id]
		var def: ItemDef = ItemDB.get_def(item_id)
		var iname: String = def.resource_name if (def != null and def.resource_name != "") else item_id.capitalize()
		var weight: float = (def.weight * count) if def != null else 0.0

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)

		if def != null and def.icon != null:
			var icon_rect := TextureRect.new()
			icon_rect.texture = def.icon
			icon_rect.custom_minimum_size = Vector2(16, 16)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			hbox.add_child(icon_rect)

		var lbl := Label.new()
		lbl.text = "• %s  x%d  (%.1f kg)" % [iname, count, weight]
		lbl.add_theme_font_size_override("font_size", 13)
		hbox.add_child(lbl)

		_item_list.add_child(hbox)
