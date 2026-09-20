class_name ItemRow
extends HBoxContainer
## One item-stack line: icon, display name, count and stack weight. The single
## row layout behind the inventory panel (InventoryItemRow inherits this scene and
## adds its action buttons) and read-only crate listings, so an item looks the same
## everywhere. Call setup() after add_child.

const _ICON_PX: float = 32.0
const _COMPACT_ICON_PX: float = 16.0
const _COMPACT_FONT_SIZE: int = 13

@onready var _icon: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _count_label: Label = %CountLabel
@onready var _weight_label: Label = %WeightLabel


func setup(def: ItemDef, count: int) -> void:
	_icon.texture = def.icon
	_name_label.text = def.get_display_name()
	_count_label.text = str(count)
	_weight_label.text = "%.1f kg" % (def.weight * count)


## Smaller icon and text for dense read-only lists such as crate contents.
func set_compact(compact: bool) -> void:
	var icon_px: float = _COMPACT_ICON_PX if compact else _ICON_PX
	_icon.custom_minimum_size = Vector2(icon_px, icon_px)
	for label: Label in [_name_label, _count_label, _weight_label]:
		if compact:
			label.add_theme_font_size_override("font_size", _COMPACT_FONT_SIZE)
		else:
			label.remove_theme_font_size_override("font_size")
